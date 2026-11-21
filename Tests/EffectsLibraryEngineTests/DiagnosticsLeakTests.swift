// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Testing
import Foundation
import EffectsLibraryCore
@testable import EffectsLibraryEngine
import EffectsLibraryTestSupport

@Suite struct DiagnosticsLeakTests {
    static let home = "/Users/jane.doe"
    /// Strings that must never appear in a support export.
    static let secretsAndNames = ["jane.doe", "AcmeCorp", "Secret Drive", "Private Clients", "hunter2", "tok_live_ABC123", "Client Footage", "SecretProject"]

    private func makeEnv() throws -> (root: URL, storage: StorageLocations, log: DiagnosticLog) {
        let root = try SyntheticFixtures.workRoot()
        let st = StorageLocations.rooted(at: root); try st.createDirectories()
        let log = DiagnosticLog(fileURL: st.logFile, appInfo: AppInfo(version: "1", build: "1"), redactor: Redactor(homePath: Self.home, pathMode: .local))
        log.warning("scan", "scan.source.failed", "cannot read \(Self.home)/Private Clients/AcmeCorp/LUTs: Permission denied")
        log.info("scan", "scan.root", "root /Volumes/Secret Drive/Client Footage/luts and ~/Private Clients/SecretProject/a.cube done")
        log.error("auth", "x", "password=hunter2 api_key=tok_live_ABC123")
        log.flush()
        let snap = InventorySnapshot(sources: [LibrarySource(id: "s1", displayName: "AcmeCorp", path: "\(Self.home)/Private Clients/AcmeCorp",
            kinds: [.lut], availability: .unavailable(reason: "Permission denied: \(Self.home)/Private Clients/AcmeCorp/LUTs"), origin: .custom)], items: [])
        try JSONStore<InventorySnapshot>(url: st.inventoryFile).save(snap)
        let j = OperationJournal(url: st.journalFile)
        try j.append("op1", .disable, .completed, itemID: "i", itemName: "Look SecretProject", from: "\(Self.home)/Private Clients/AcmeCorp/Look.cube",
                     to: "/Volumes/Secret Drive/Client Footage/Look.cube", sameVolume: false, message: "token=tok_live_ABC123")
        try Data("{\"disabledRoot\":\"\(Self.home)/Private Clients\",\"apiToken\":\"tok_live_ABC123\"}".utf8).write(to: st.settingsFile)
        return (root, st, log)
    }

    private func unzipAll(_ zip: URL, into dir: URL) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-o", "-q", zip.path, "-d", dir.path]
        try p.run(); p.waitUntilExit(); #expect(p.terminationStatus == 0)
        var all = ""
        for case let u as URL in FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)! where !u.hasDirectoryPath {
            all += (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        }
        return all
    }

    @Test func supportExportLeaksNothingPersonal() throws {
        let (root, st, log) = try makeEnv(); defer { try? FileManager.default.removeItem(at: root) }
        let s = try DiagnosticsExporter(log: log, storage: st, appInfo: AppInfo(version: "1", build: "1"), homePath: Self.home)
            .export(to: root.appendingPathComponent("out"), includePaths: false)
        let text = try unzipAll(s.url, into: root.appendingPathComponent("x"))
        for needle in Self.secretsAndNames { #expect(!text.contains(needle), "leaked: \(needle)") }
    }

    @Test func includePathsKeepsPathsButStillRedactsSecrets() throws {
        let (root, st, log) = try makeEnv(); defer { try? FileManager.default.removeItem(at: root) }
        let s = try DiagnosticsExporter(log: log, storage: st, appInfo: AppInfo(version: "1", build: "1"), homePath: Self.home)
            .export(to: root.appendingPathComponent("out"), includePaths: true)
        let text = try unzipAll(s.url, into: root.appendingPathComponent("x"))
        #expect(text.contains("Private Clients"))                               // the owner chose to include paths
        for secret in ["hunter2", "tok_live_ABC123"] { #expect(!text.contains(secret), "secret leaked: \(secret)") }
    }

    @Test func spacedAndTildePathsAreFullyAnonymized() {
        let r = Redactor(homePath: Self.home, pathMode: .support)
        let out = r.redact("a /Volumes/Secret Drive/Client Footage/x.cube; b ~/Private Clients/SecretProject/a.cube, c \(Self.home)/Private Clients/AcmeCorp/LUTs")
        for needle in ["Secret", "Client", "Private", "AcmeCorp", "jane"] { #expect(!out.contains(needle), "leaked \(needle): \(out)") }
        #expect(out.contains(".cube"))
    }
}
