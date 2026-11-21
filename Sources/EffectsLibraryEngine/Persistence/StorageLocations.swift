// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Where the app keeps its own data. Product default = standard macOS locations; tests/dev inject another root
/// (for development this is how outputs are kept on external storage). No machine-specific path lives here.
public struct StorageLocations: Sendable {
    public let appSupport: URL
    public let caches: URL
    public let logs: URL

    public init(appSupport: URL, caches: URL, logs: URL) {
        self.appSupport = appSupport; self.caches = caches; self.logs = logs
    }

    public static let defaultBundleID = "dev.gordas.GDCEffectsLibrary"

    public static func standard(bundleID: String = defaultBundleID) -> StorageLocations {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID, isDirectory: true)
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID, isDirectory: true)
        let logs = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/GDCEffectsLibrary", isDirectory: true)
        return StorageLocations(appSupport: support, caches: caches, logs: logs)
    }

    /// Everything under one root (tests, benchmarks, development runs).
    public static func rooted(at root: URL) -> StorageLocations {
        StorageLocations(appSupport: root.appendingPathComponent("support", isDirectory: true),
                         caches: root.appendingPathComponent("caches", isDirectory: true),
                         logs: root.appendingPathComponent("logs", isDirectory: true))
    }

    /// `GEL_STORAGE_ROOT` (development/test override) or the standard macOS locations.
    public static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> StorageLocations {
        if let root = env["GEL_STORAGE_ROOT"], !root.isEmpty { return rooted(at: URL(fileURLWithPath: root, isDirectory: true)) }
        return standard()
    }

    public var sourcesFile: URL { appSupport.appendingPathComponent("sources.json") }
    public var inventoryFile: URL { appSupport.appendingPathComponent("inventory.json") }
    public var settingsFile: URL { appSupport.appendingPathComponent("settings.json") }
    public var journalFile: URL { appSupport.appendingPathComponent("operations.jsonl") }
    /// Product details (associations, provenance, user choices). Application Support: survives cache clearing.
    public var enrichmentFile: URL { appSupport.appendingPathComponent("enrichment.json") }
    /// Images the user picked: Application Support, never evicted automatically.
    public var userCoversDir: URL { appSupport.appendingPathComponent("covers-user", isDirectory: true) }
    /// Covers fetched online: a re-fetchable cache (Caches), size-capped, separate from preview renders.
    public var fetchedCoversDir: URL { caches.appendingPathComponent("covers", isDirectory: true) }
    public var previewCacheDir: URL { caches.appendingPathComponent("previews", isDirectory: true) }
    public var logFile: URL { logs.appendingPathComponent("GDCEffectsLibrary.log") }

    public func createDirectories() throws {
        for u in [appSupport, caches, logs] { try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true) }
    }
}
