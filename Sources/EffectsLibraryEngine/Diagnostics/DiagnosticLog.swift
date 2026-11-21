// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import os

public enum LogLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    case trace, debug, info, warning, error, critical
    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
    public var name: String { String(describing: self) }
}

public struct LogEntry: Codable, Sendable, Equatable {
    public var timestamp: String      // ISO-8601 with time zone offset
    public var level: String
    public var subsystem: String
    public var event: String          // stable event id, e.g. "scan.source.done"
    public var session: String
    public var correlation: String?
    public var appVersion: String
    public var platform: String
    public var message: String
    public var fields: [String: String]
}

public struct AppInfo: Sendable {
    public var version: String
    public var build: String
    public var platform: String
    public init(version: String, build: String,
                platform: String = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)") {
        self.version = version; self.build = build; self.platform = platform
    }
    public static let unknown = AppInfo(version: "0.0.0", build: "0")
}

/// Propagates an operation id (scan, preview batch, move…) through structured concurrency.
public enum Correlation {
    @TaskLocal public static var id: String?
    public static func newID(_ prefix: String) -> String { "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())" }
}

/// Structured, rotating, redacting JSON-lines log. Writing never throws and never blocks the caller's operation:
/// entries go through a serial queue; any I/O failure is counted and swallowed (fallback = os_log only).
public final class DiagnosticLog: @unchecked Sendable {
    public let sessionID = String(UUID().uuidString.prefix(8).lowercased())
    public let fileURL: URL
    public let maxBytes: Int
    public let maxFiles: Int
    private let appInfo: AppInfo
    private let redactor: Redactor
    private let queue = DispatchQueue(label: "dev.gordas.GDCEffectsLibrary.log")
    private let lock = NSLock()
    private var _minLevel: LogLevel = .info
    private var _debugUntil: Date?
    private var _failedWrites = 0
    private let os = Logger(subsystem: StorageLocations.defaultBundleID, category: "app")
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        f.timeZone = .current; return f
    }()

    public init(fileURL: URL, appInfo: AppInfo, maxBytes: Int = 2 * 1024 * 1024, maxFiles: Int = 5,
                redactor: Redactor = Redactor()) {
        self.fileURL = fileURL; self.appInfo = appInfo; self.maxBytes = maxBytes
        self.maxFiles = max(1, maxFiles); self.redactor = redactor
    }

    public var failedWrites: Int { lock.withLock { _failedWrites } }

    /// Temporary verbose logging: in memory only, so it ends by itself at the next launch.
    public func enableDebug(for seconds: TimeInterval) { lock.withLock { _debugUntil = Date().addingTimeInterval(seconds) } }
    public func disableDebug() { lock.withLock { _debugUntil = nil } }
    public var debugEnabled: Bool { lock.withLock { if let u = _debugUntil, u > Date() { return true }; return false } }

    public func write(_ level: LogLevel, _ subsystem: String, _ event: String, _ message: String = "",
                      correlation: String? = Correlation.id, fields: [String: String] = [:]) {
        let effective: LogLevel = debugEnabled ? .trace : lock.withLock { _minLevel }
        guard level >= effective else { return }
        let entry = LogEntry(timestamp: iso.string(from: Date()), level: level.name, subsystem: subsystem, event: event,
                             session: sessionID, correlation: correlation, appVersion: "\(appInfo.version) (\(appInfo.build))",
                             platform: appInfo.platform, message: redactor.redact(message),
                             fields: fields.mapValues { redactor.redact($0) })
        os.log(level: level >= .error ? .error : .info, "\(subsystem, privacy: .public) \(event, privacy: .public) \(entry.message, privacy: .public)")
        queue.async { [self] in append(entry) }
    }

    public func info(_ sub: String, _ event: String, _ message: String = "", fields: [String: String] = [:]) { write(.info, sub, event, message, fields: fields) }
    public func warning(_ sub: String, _ event: String, _ message: String = "", fields: [String: String] = [:]) { write(.warning, sub, event, message, fields: fields) }
    public func error(_ sub: String, _ event: String, _ message: String = "", fields: [String: String] = [:]) { write(.error, sub, event, message, fields: fields) }
    public func debug(_ sub: String, _ event: String, _ message: String = "", fields: [String: String] = [:]) { write(.debug, sub, event, message, fields: fields) }

    /// Waits for queued entries (shutdown, tests, export).
    public func flush() { queue.sync {} }

    /// All log files, oldest first (`.4`, `.3`, …, active).
    public func allFiles() -> [URL] {
        var out: [URL] = []
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let u = rotated(i); if FileManager.default.fileExists(atPath: u.path) { out.append(u) }
        }
        if FileManager.default.fileExists(atPath: fileURL.path) { out.append(fileURL) }
        return out
    }

    private func rotated(_ i: Int) -> URL { fileURL.deletingLastPathComponent().appendingPathComponent(fileURL.lastPathComponent + ".\(i)") }

    private func append(_ entry: LogEntry) {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var line = try JSONEncoder.sorted.encode(entry); line.append(0x0A)
            let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            if size + line.count > maxBytes, size > 0 { try rotate() }
            if !fm.fileExists(atPath: fileURL.path) { fm.createFile(atPath: fileURL.path, contents: nil) }
            let h = try FileHandle(forWritingTo: fileURL)
            defer { try? h.close() }
            try h.seekToEnd(); try h.write(contentsOf: line)
        } catch {
            lock.withLock { _failedWrites += 1 }   // fallback: the os_log mirror above already has the entry
        }
    }

    private func rotate() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: rotated(maxFiles - 1))
        if maxFiles > 2 { for i in stride(from: maxFiles - 2, through: 1, by: -1) where fm.fileExists(atPath: rotated(i).path) {
            try fm.moveItem(at: rotated(i), to: rotated(i + 1)) } }
        if maxFiles > 1 { try fm.moveItem(at: fileURL, to: rotated(1)) } else { try fm.removeItem(at: fileURL) }
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e }
}
