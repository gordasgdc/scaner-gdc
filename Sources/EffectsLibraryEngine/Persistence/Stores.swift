// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore

extension JSONDecoder { static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }
extension JSONEncoder {
    static var isoPretty: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
}

/// Last known inventory. Versioned: `schemaVersion` mismatch → migration, never a silent decode failure.
public struct InventorySnapshot: Codable, Sendable {
    public static let currentSchema = 1
    public var schemaVersion: Int
    public var savedAt: Date
    public var sources: [LibrarySource]
    public var items: [EffectItem]
    public init(sources: [LibrarySource], items: [EffectItem], savedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchema; self.savedAt = savedAt; self.sources = sources; self.items = items
    }
}

/// A user-chosen source. `bookmark` follows the folder if it is moved/renamed; `path` is the last resolved path.
public struct CustomSourceRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var path: String
    public var bookmark: Data?
    public var kinds: Set<ItemKind>
    public var displayName: String
    public init(path: String, kinds: Set<ItemKind>, bookmark: Data?, displayName: String? = nil) {
        self.path = path; self.kinds = kinds; self.bookmark = bookmark
        self.displayName = displayName ?? (path as NSString).lastPathComponent
        self.id = "custom-" + StableID.make(kind: .lut, bundleIdentifier: nil, path: path).prefix(10)
    }
}

public struct SourcesFile: Codable, Sendable {
    public static let currentSchema = 1
    public var schemaVersion = SourcesFile.currentSchema
    public var custom: [CustomSourceRecord] = []
    /// Disabled-store location chosen by the user (nil = sibling folder next to each source).
    public var disabledRootOverride: String?
    public init(custom: [CustomSourceRecord] = [], disabledRootOverride: String? = nil) {
        self.custom = custom; self.disabledRootOverride = disabledRootOverride
    }
}

public enum StoreError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(found: Int, supported: Int)
    case corrupt(String)
    public var description: String {
        switch self {
        case .unsupportedSchema(let f, let s): "Data file was written by a newer version (schema \(f), supported \(s))"
        case .corrupt(let m): "Data file is unreadable: \(m)"
        }
    }
}

/// Atomic JSON persistence. A corrupt file is moved aside (`.corrupt-<ts>`), never silently dropped or overwritten.
public struct JSONStore<T: Codable & Sendable>: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do { return try JSONDecoder.iso.decode(T.self, from: data) }
        catch {
            let aside = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: aside)
            throw StoreError.corrupt("\(error.localizedDescription) (kept as \(aside.lastPathComponent))")
        }
    }

    public func save(_ value: T) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.isoPretty.encode(value).write(to: url, options: .atomic)
    }
}

public extension JSONStore where T == InventorySnapshot {
    /// Loads and validates the schema. Older schemas would be migrated here (none exist yet).
    func loadValidated() throws -> InventorySnapshot? {
        guard let s = try load() else { return nil }
        if s.schemaVersion > InventorySnapshot.currentSchema { throw StoreError.unsupportedSchema(found: s.schemaVersion, supported: InventorySnapshot.currentSchema) }
        return s
    }
}
public extension JSONStore where T == SourcesFile {
    func loadValidated() throws -> SourcesFile? {
        guard let s = try load() else { return nil }
        if s.schemaVersion > SourcesFile.currentSchema { throw StoreError.unsupportedSchema(found: s.schemaVersion, supported: SourcesFile.currentSchema) }
        return s
    }
}
