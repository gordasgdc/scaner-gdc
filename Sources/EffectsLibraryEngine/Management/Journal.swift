// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

public enum OperationKind: String, Codable, Sendable { case disable, restore }

public enum OperationPhase: String, Codable, Sendable {
    case planned, started            // intent recorded / about to touch the filesystem
    case copying, verified           // cross-volume only
    case committed                   // destination in place
    case trashedSource               // cross-volume: original moved to Trash
    case completed, aborted, failed, recovered
    public var isTerminal: Bool { self == .completed || self == .aborted || self == .failed }
}

public struct JournalEntry: Codable, Sendable, Equatable {
    public var seq: Int
    public var timestamp: Date
    public var opID: String
    public var kind: OperationKind
    public var phase: OperationPhase
    public var itemID: String
    public var itemName: String
    public var from: String
    public var to: String
    public var sameVolume: Bool
    /// Where the item lived before being disabled (copied onto restore ops).
    public var originalPath: String?
    public var manifestDigest: String?
    public var correlation: String?
    public var message: String
}

/// Append-only, fsync'd operation journal (JSON lines). The single source of truth for recovery and for Restore.
public final class OperationJournal: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private let enc: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e }()

    public init(url: URL) { self.url = url }

    @discardableResult
    public func append(_ opID: String, _ kind: OperationKind, _ phase: OperationPhase, itemID: String, itemName: String, from: String, to: String,
                       sameVolume: Bool, originalPath: String? = nil, digest: String? = nil, message: String = "") throws -> JournalEntry {
        try lock.withLock {
            let seq = (try? loadLocked().last?.seq).flatMap { $0 }.map { $0 + 1 } ?? 1
            let e = JournalEntry(seq: seq, timestamp: Date(), opID: opID, kind: kind, phase: phase, itemID: itemID, itemName: itemName, from: from, to: to,
                                 sameVolume: sameVolume, originalPath: originalPath, manifestDigest: digest, correlation: Correlation.id, message: message)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var line = try enc.encode(e); line.append(0x0A)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            let h = try FileHandle(forWritingTo: url); defer { try? h.close() }
            try h.seekToEnd(); try h.write(contentsOf: line); try h.synchronize()
            return e
        }
    }

    public func entries() -> [JournalEntry] { lock.withLock { (try? loadLocked()) ?? [] } }

    private func loadLocked() throws -> [JournalEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        var out: [JournalEntry] = []
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            if let e = try? dec.decode(JournalEntry.self, from: Data(line.utf8)) { out.append(e) }   // a torn last line is ignored
        }
        return out
    }

    /// Last entry per operation, in order of first appearance.
    public func latestPerOperation() -> [JournalEntry] {
        var order: [String] = [], last: [String: JournalEntry] = [:]
        for e in entries() { if last[e.opID] == nil { order.append(e.opID) }; last[e.opID] = e }
        return order.compactMap { last[$0] }
    }

    public func incomplete() -> [JournalEntry] { latestPerOperation().filter { !$0.phase.isTerminal && $0.phase != .recovered } }

    /// Active disable records: completed disables whose destination has not been restored.
    public func disabledRecord(atPath path: String) -> JournalEntry? {
        let ops = latestPerOperation()
        guard let d = ops.last(where: { $0.kind == .disable && $0.phase == .completed && $0.to == path }) else { return nil }
        if ops.contains(where: { $0.kind == .restore && $0.phase == .completed && $0.from == path && $0.seq > d.seq }) { return nil }
        return d
    }
}
