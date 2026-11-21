// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore
import CryptoKit

/// Builds the local, inspectable diagnostic package. Never uploads. Contains only whitelisted content:
/// redacted logs, manifest, version/platform, non-sensitive settings, and short scan/operation summaries.
/// No media, no plugin/LUT contents, no credentials.
public struct DiagnosticsExporter: Sendable {
    public struct Summary: Sendable { public var url: URL; public var files: [String]; public var includesPaths: Bool }

    private let log: DiagnosticLog
    private let storage: StorageLocations
    private let appInfo: AppInfo
    private let homePath: String

    public init(log: DiagnosticLog, storage: StorageLocations, appInfo: AppInfo, homePath: String = NSHomeDirectory()) {
        self.log = log; self.storage = storage; self.appInfo = appInfo; self.homePath = homePath
    }

    @discardableResult
    public func export(to directory: URL, includePaths: Bool = false, now: Date = Date()) throws -> Summary {
        log.flush()
        let redactor = Redactor(homePath: homePath, pathMode: includePaths ? .includePaths : .support)
        var zip = ZipWriter()
        var manifestFiles: [[String: String]] = []
        func add(_ path: String, _ data: Data) {
            zip.add(path: path, data: data, date: now)
            manifestFiles.append(["path": path, "bytes": String(data.count),
                                  "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()])
        }
        // Logs (redacted again with the support-mode redactor).
        for f in log.allFiles() {
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            add("logs/" + f.lastPathComponent, Data(redactor.redact(text).utf8))
        }
        // Whitelisted state: summaries only.
        if let inv = try? Data(contentsOf: storage.inventoryFile), let s = Self.inventorySummary(inv) { add("state/scan-summary.json", s) }
        if let j = try? String(contentsOf: storage.journalFile, encoding: .utf8) {
            // File/plugin names can carry project or client names: dropped from support exports unless paths were chosen.
            let lines = j.split(separator: "\n").map { line -> String in
                guard !includePaths, var o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return String(line) }
                if o["itemName"] != nil { o["itemName"] = "<item>" }
                let d = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
                return String(decoding: d, as: UTF8.self)
            }
            add("state/operations.jsonl", Data(redactor.redact(lines.joined(separator: "\n") + "\n").utf8))
        }
        if let st = try? String(contentsOf: storage.settingsFile, encoding: .utf8) { add("settings.json", Data(redactor.redact(st).utf8)) }

        let info: [String: Any] = [
            "app": "Scaner GDC", "version": appInfo.version, "build": appInfo.build, "platform": appInfo.platform,
            "session": log.sessionID, "generated": ISO8601DateFormatter().string(from: now), "includesPaths": includePaths,
            "note": "Local package, never uploaded automatically. Contains no media, plugin/LUT contents or credentials.",
            "files": manifestFiles,
        ]
        let manifest = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        zip.add(path: "manifest.json", data: manifest, date: now)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("GDCEffectsLibrary-diagnostics-\(stamp).zip")
        try zip.finish().write(to: url, options: .atomic)
        log.info("diagnostics", "diagnostics.export", "exported", fields: ["files": String(manifestFiles.count + 1), "includePaths": String(includePaths)])
        return Summary(url: url, files: manifestFiles.compactMap { $0["path"] } + ["manifest.json"], includesPaths: includePaths)
    }

    /// Only the kind of availability; the reason text can contain paths and is deliberately dropped.
    static func statusKind(_ a: SourceAvailability) -> String {
        switch a { case .available: "available"; case .unavailable: "unavailable"; case .missing: "missing"; case .notScanned: "notScanned" }
    }

    /// Counts only: no item names or paths.
    static func inventorySummary(_ data: Data) -> Data? {
        guard let snap = try? JSONDecoder.iso.decode(InventorySnapshot.self, from: data) else { return nil }
        var perKind: [String: Int] = [:]; for i in snap.items { perKind[i.kind.rawValue, default: 0] += 1 }
        let sources = snap.sources.map { ["id": $0.id, "origin": $0.origin.rawValue, "status": Self.statusKind($0.availability),
                                          "lastScan": $0.lastScan.map { ISO8601DateFormatter().string(from: $0) } ?? "never"] }
        let d: [String: Any] = ["schemaVersion": snap.schemaVersion, "itemCount": snap.items.count, "perKind": perKind, "sources": sources]
        return try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys])
    }
}
