// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import CryptoKit

/// Cache identity: any change in LUT content, renderer version, settings or reference produces a different key,
/// so stale previews are never served (invalidation by construction).
public struct PreviewKey: Sendable, Hashable {
    public let value: String
    public init(contentHash: String, rendererVersion: Int = LUTPreviewRenderer.version, settings: String, referenceID: String, referenceHash: String) {
        let material = [contentHash, "r\(rendererVersion)", settings, referenceID, referenceHash].joined(separator: "|")
        value = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public init(raw: String) { value = raw }
}

/// Size-capped, LRU-evicting, atomically written on-disk cache of PNG previews.
public final class PreviewCache: @unchecked Sendable {
    public let directory: URL
    public let maxBytes: Int
    private let lock = NSLock()
    private let fm = FileManager.default

    public init(directory: URL, maxBytes: Int = 64 * 1024 * 1024) { self.directory = directory; self.maxBytes = maxBytes }

    private func file(_ k: PreviewKey) -> URL { directory.appendingPathComponent(k.value + ".png") }

    /// A hit refreshes the entry's recency. A corrupt entry (not a PNG) is deleted and reported as a miss.
    public func get(_ k: PreviewKey) -> Data? {
        lock.withLock {
            let u = file(k)
            guard let d = try? Data(contentsOf: u) else { return nil }
            guard d.count > 8, d.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { try? fm.removeItem(at: u); return nil }
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: u.path)
            return d
        }
    }

    /// Atomic write, then eviction. An entry larger than the whole cap is not stored.
    @discardableResult
    public func put(_ k: PreviewKey, _ data: Data) -> Bool {
        guard data.count <= maxBytes else { return false }
        return lock.withLock {
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: file(k), options: .atomic)
            } catch { return false }
            evictLocked(keeping: file(k))
            return true
        }
    }

    public var totalBytes: Int { lock.withLock { entriesLocked().reduce(0) { $0 + $1.size } } }
    public var count: Int { lock.withLock { entriesLocked().count } }

    public func removeAll() { lock.withLock { try? fm.removeItem(at: directory) } }

    /// Drops every entry whose key is not in `keep` (e.g. after the inventory changed).
    public func prune(keeping keep: Set<PreviewKey>) {
        lock.withLock { let names = Set(keep.map { $0.value + ".png" })
            for e in entriesLocked() where !names.contains(e.url.lastPathComponent) { try? fm.removeItem(at: e.url) } }
    }

    private struct Entry { let url: URL; let size: Int; let date: Date }
    private func entriesLocked() -> [Entry] {
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return [] }
        return urls.filter { $0.pathExtension == "png" }.compactMap { u in
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return Entry(url: u, size: v?.fileSize ?? 0, date: v?.contentModificationDate ?? .distantPast)
        }
    }
    private func evictLocked(keeping: URL) {
        var es = entriesLocked(); var total = es.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        es.sort { $0.date < $1.date }
        for e in es where total > maxBytes && e.url != keeping { try? fm.removeItem(at: e.url); total -= e.size }
    }
}
