// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore

public struct EnrichmentFile: Codable, Sendable {
    public static let currentSchema = 1
    public var schemaVersion = EnrichmentFile.currentSchema
    public var records: [String: ProductRecord] = [:]
    /// Temporary "nothing found" results: key → time of the miss (expire after a TTL; never stored as a rejection).
    public var notFound: [String: Date] = [:]
    public init() {}
}

/// Product details, kept apart from scanned metadata. Metadata (JSON, Application Support) and images live in different folders:
/// user-chosen images in Application Support (never evicted), fetched covers in Caches (re-fetchable from the recorded source).
public actor EnrichmentStore {
    public static let negativeTTL: TimeInterval = 24 * 3600
    public static let fetchedCoverCapBytes = 64 * 1024 * 1024
    private let loc: StorageLocations
    private let json: JSONStore<EnrichmentFile>
    private var file = EnrichmentFile()
    private var loaded = false
    private let fm = FileManager.default

    public init(locations: StorageLocations) { loc = locations; json = JSONStore(url: locations.enrichmentFile) }

    // MARK: load / save (versioned, atomic; a corrupt file is kept aside by JSONStore)

    @discardableResult
    public func load() throws -> EnrichmentFile {
        defer { loaded = true }
        if let f = try json.load() {
            if f.schemaVersion > EnrichmentFile.currentSchema { throw StoreError.unsupportedSchema(found: f.schemaVersion, supported: EnrichmentFile.currentSchema) }
            file = f
        }
        return file
    }
    private func ensureLoaded() { if !loaded { _ = try? load(); loaded = true } }
    private func save() { try? json.save(file) }

    // MARK: records

    public func record(_ key: String) -> ProductRecord? { ensureLoaded(); return file.records[key] }
    public func allRecords() -> [String: ProductRecord] { ensureLoaded(); return file.records }

    public func upsert(_ r: ProductRecord) { ensureLoaded(); var r = r; r.updatedAt = Date(); file.records[r.key] = r; file.notFound[r.key] = nil; save() }

    /// "Associate official page": a user choice, confirmed immediately. Never overwritten by automatic lookups.
    public func setOfficialURL(key: String, url: URL) -> ProductRecord {
        ensureLoaded(); var r = file.records[key] ?? ProductRecord(key: key, status: .confirmed)
        r.officialURL = url.absoluteString; r.userChoseURL = true; r.status = .confirmed; r.updatedAt = Date()
        file.records[key] = r; file.notFound[key] = nil; save(); return r
    }

    public func setUserImage(key: String, clean: ImageSanitizer.Clean) throws -> ProductRecord {
        ensureLoaded()
        try fm.createDirectory(at: loc.userCoversDir, withIntermediateDirectories: true)
        try clean.png.write(to: loc.userCoversDir.appendingPathComponent(clean.fileName), options: .atomic)
        var r = file.records[key] ?? ProductRecord(key: key, status: .confirmed)
        let old = r.cover
        r.cover = CoverImageRef(fileName: clean.fileName, origin: .userLocal, rights: .userSupplied, sourceURL: nil, pixelWidth: clean.width, pixelHeight: clean.height)
        r.userChoseImage = true; r.status = .confirmed; r.proposedImageURL = nil; r.updatedAt = Date()
        file.records[key] = r; file.notFound[key] = nil; save()
        if let old { removeCoverFileIfUnused(old, except: key) }
        return r
    }

    public func setFetchedCover(key: String, clean: ImageSanitizer.Clean, sourceURL: URL) throws -> ProductRecord {
        ensureLoaded()
        try fm.createDirectory(at: loc.fetchedCoversDir, withIntermediateDirectories: true)
        try clean.png.write(to: loc.fetchedCoversDir.appendingPathComponent(clean.fileName), options: .atomic)
        var r = file.records[key] ?? ProductRecord(key: key, status: .confirmed)
        r.cover = CoverImageRef(fileName: clean.fileName, origin: .officialPage, rights: .pageDeclaredPreview, sourceURL: sourceURL.absoluteString, pixelWidth: clean.width, pixelHeight: clean.height)
        r.proposedImageURL = nil; r.status = .confirmed; r.updatedAt = Date()
        file.records[key] = r; save(); evictFetchedCovers()
        return r
    }

    public func reject(key: String) {
        ensureLoaded(); var r = file.records[key] ?? ProductRecord(key: key)
        r.status = .rejected; r.proposedImageURL = nil; r.updatedAt = Date(); file.records[key] = r; save()
    }

    /// "Remove cover and online data": drops the record, including a user-chosen image the user asked to remove.
    public func remove(key: String) {
        ensureLoaded()
        if let c = file.records[key]?.cover { file.records[key] = nil; removeCoverFileIfUnused(c, except: key) }
        file.records[key] = nil; file.notFound[key] = nil; save()
    }

    // MARK: temporary negative results

    public func markNotFound(_ key: String, now: Date = Date()) { ensureLoaded(); file.notFound[key] = now; save() }
    public func isRecentlyNotFound(_ key: String, now: Date = Date()) -> Bool {
        ensureLoaded(); guard let t = file.notFound[key] else { return false }; return now.timeIntervalSince(t) < Self.negativeTTL
    }

    // MARK: images

    public func coverData(for r: ProductRecord) -> Data? {
        guard let c = r.cover else { return nil }
        let dir = c.origin == .userLocal ? loc.userCoversDir : loc.fetchedCoversDir
        let u = dir.appendingPathComponent(c.fileName)
        guard let d = try? Data(contentsOf: u), ImageSanitizer.sniff(d) == .png else { return nil }
        if c.origin == .officialPage { try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: u.path) }
        return d
    }

    /// Clearing the cache removes fetched images only. Records (associations, provenance, choices) and user images stay.
    public func clearFetchedCovers() { try? fm.removeItem(at: loc.fetchedCoversDir) }

    private func removeCoverFileIfUnused(_ c: CoverImageRef, except key: String) {
        let shared = file.records.values.contains { $0.key != key && $0.cover?.fileName == c.fileName && $0.cover?.origin == c.origin }
        if shared { return }
        let dir = c.origin == .userLocal ? loc.userCoversDir : loc.fetchedCoversDir
        try? fm.removeItem(at: dir.appendingPathComponent(c.fileName))
    }

    private func evictFetchedCovers() {
        guard let urls = try? fm.contentsOfDirectory(at: loc.fetchedCoversDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var es = urls.compactMap { u -> (URL, Int, Date)? in let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]); return (u, v?.fileSize ?? 0, v?.contentModificationDate ?? .distantPast) }
        var total = es.reduce(0) { $0 + $1.1 }; guard total > Self.fetchedCoverCapBytes else { return }
        es.sort { $0.2 < $1.2 }
        for e in es where total > Self.fetchedCoverCapBytes { try? fm.removeItem(at: e.0); total -= e.1 }
    }
}
