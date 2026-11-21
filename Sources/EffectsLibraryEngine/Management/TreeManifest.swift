// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import CryptoKit

/// Structural + content fingerprint of a file or bundle tree: types, sizes, symlink targets, extended attributes
/// (so `com.apple.quarantine` and signatures' xattrs are compared, never altered) and optionally content hashes.
public struct TreeManifest: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var type: String          // "dir" | "file" | "link"
        public var size: Int64
        public var link: String?
        public var sha256: String?
        public var xattrs: [String: String]   // name → sha256 of value
    }
    public var entries: [String: Entry]
    public var withContents: Bool

    public var totalBytes: Int64 { entries.values.filter { $0.type == "file" }.reduce(0) { $0 + $1.size } }
    public var count: Int { entries.count }

    /// Short stable digest of the whole manifest.
    public var digest: String {
        var h = SHA256()
        for k in entries.keys.sorted() {
            let e = entries[k]!
            h.update(data: Data("\(k)|\(e.type)|\(e.size)|\(e.link ?? "")|\(e.sha256 ?? "")|\(e.xattrs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))\n".utf8))
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func build(at root: URL, withContents: Bool, maxEntries: Int = 200_000) throws -> TreeManifest {
        let fm = FileManager.default
        var out: [String: Entry] = [:]
        func entry(_ url: URL) throws -> Entry {
            var st = stat()
            guard lstat(url.path, &st) == 0 else { throw ManifestError.unreadable(url.lastPathComponent, errno) }
            let mode = st.st_mode & S_IFMT
            var e = Entry(type: mode == S_IFDIR ? "dir" : mode == S_IFLNK ? "link" : "file", size: mode == S_IFREG ? Int64(st.st_size) : 0,
                          link: nil, sha256: nil, xattrs: xattrs(url.path))
            if mode == S_IFLNK { e.link = (try? fm.destinationOfSymbolicLink(atPath: url.path)) ?? "" }
            if withContents, mode == S_IFREG { guard let h = ContentHasher.sha256(of: url) else { throw ManifestError.unreadable(url.lastPathComponent, EACCES) }; e.sha256 = h }
            return e
        }
        out["."] = try entry(root)
        if out["."]!.type == "dir", let en = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: nil) {
            let base = root.standardizedFileURL.path
            while let obj = en.nextObject() {
                guard let u = obj as? URL else { continue }
                let rel = String(u.standardizedFileURL.path.dropFirst(base.count + 1))
                out[rel] = try entry(u)
                if out.count > maxEntries { throw ManifestError.tooManyEntries(maxEntries) }
            }
        }
        return TreeManifest(entries: out, withContents: withContents)
    }

    static func xattrs(_ path: String) -> [String: String] {
        let n = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        guard n > 0 else { return [:] }
        var buf = [CChar](repeating: 0, count: n)
        guard listxattr(path, &buf, n, XATTR_NOFOLLOW) >= 0 else { return [:] }
        var out: [String: String] = [:]
        for name in buf.split(separator: 0).map({ String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }) {
            let sz = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            var v = [UInt8](repeating: 0, count: max(sz, 0))
            if sz > 0 { _ = getxattr(path, name, &v, sz, 0, XATTR_NOFOLLOW) }
            out[name] = SHA256.hash(data: Data(v)).map { String(format: "%02x", $0) }.joined()
        }
        return out
    }

    /// Human-readable differences (empty = identical).
    public func differences(from other: TreeManifest, limit: Int = 5) -> [String] {
        var d: [String] = []
        for k in Set(entries.keys).union(other.entries.keys).sorted() {
            if entries[k] != other.entries[k] { d.append(entries[k] == nil ? "extra: \(k)" : other.entries[k] == nil ? "missing: \(k)" : "differs: \(k)") }
            if d.count >= limit { break }
        }
        return d
    }
}

public enum ManifestError: Error, CustomStringConvertible {
    case unreadable(String, Int32), tooManyEntries(Int)
    public var description: String {
        switch self { case .unreadable(let n, let e): "Cannot read \(n) (errno \(e))"; case .tooManyEntries(let n): "More than \(n) entries" }
    }
}
