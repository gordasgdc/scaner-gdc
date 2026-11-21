// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Testing
import Foundation
import EffectsLibraryEngine
import EffectsLibraryTestSupport

@Suite struct DiagnosticsTests {
    @Test func redactsSecretsEmailsAndTokens() {
        let r = Redactor(homePath: "/Users/someone", pathMode: .local)
        let out = r.redact("password=hunter2 token: abc123 license_key=\"AAAA-BBBB\" mail me at a.b@example.com Authorization: Bearer xyz.123 /Users/someone/Docs deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
        #expect(!out.contains("hunter2")); #expect(!out.contains("abc123")); #expect(!out.contains("AAAA-BBBB"))
        #expect(!out.contains("a.b@example.com")); #expect(!out.contains("xyz.123")); #expect(!out.contains("deadbeefdead"))
        #expect(out.contains("~/Docs")); #expect(!out.contains("/Users/someone"))
    }
    @Test func supportModeAnonymizesUserAndVolumePathsButKeepsSystemPaths() {
        let r = Redactor(homePath: "/Users/someone", pathMode: .support)
        let out = r.redact("a /Users/someone/Movies/ClientX/clip.mov; b /Volumes/Secret Drive/p/file.cube; c /Library/OFX/Plugins/A.ofx.bundle")
        #expect(!out.contains("someone")); #expect(!out.contains("ClientX")); #expect(!out.contains("Secret")); #expect(!out.contains("Drive"))
        #expect(out.contains(".mov")); #expect(out.contains("/Library/OFX/Plugins/A.ofx.bundle"))
        let keep = Redactor(homePath: "/Users/someone", pathMode: .includePaths).redact("/Users/someone/Movies/clip.mov")
        #expect(keep.contains("clip.mov"))
    }
    @Test func rotationRespectsSizeAndFileCount() throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(fileURL: root.appendingPathComponent("t.log"), appInfo: .unknown, maxBytes: 2_000, maxFiles: 3)
        for i in 0..<400 { log.info("test", "t.event", "line \(i) " + String(repeating: "x", count: 40)) }
        log.flush()
        let files = log.allFiles()
        #expect(files.count <= 3); #expect(files.count >= 2)
        for f in files { #expect((try FileManager.default.attributesOfItem(atPath: f.path)[.size] as! Int) <= 2_000 + 600) }
        #expect(log.failedWrites == 0)
    }
    @Test func entriesAreStructuredAndCorrelatedAcrossConcurrentJobs() async throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(fileURL: root.appendingPathComponent("c.log"), appInfo: AppInfo(version: "9.9", build: "7"))
        await withTaskGroup(of: Void.self) { g in
            for j in 0..<6 { g.addTask { await Correlation.$id.withValue("job-\(j)") {
                for k in 0..<20 { log.info("test", "job.step", "step \(k)", fields: ["k": "\(k)"]); await Task.yield() } } } }
        }
        log.flush()
        let lines = try String(contentsOf: log.fileURL, encoding: .utf8).split(separator: "\n")
        let entries = try lines.map { try JSONDecoder().decode(LogEntry.self, from: Data($0.utf8)) }
        #expect(entries.count == 120)
        let grouped = Dictionary(grouping: entries, by: { $0.correlation ?? "-" })
        #expect(grouped.count == 6)
        for (_, e) in grouped { #expect(e.count == 20); #expect(e.map { Int($0.fields["k"]!)! } == Array(0..<20)) }
        let e = entries[0]
        #expect(e.appVersion == "9.9 (7)"); #expect(e.session == log.sessionID); #expect(e.timestamp.contains("T"))
        #expect(e.platform.contains("macOS")); #expect(!e.event.isEmpty)
    }
    @Test func brokenLoggerNeverBlocksOrThrows() throws {
        let root = try SyntheticFixtures.workRoot(); defer { chmod(root.path, 0o755); try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("ro"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        chmod(dir.path, 0o500)
        let log = DiagnosticLog(fileURL: dir.appendingPathComponent("sub/x.log"), appInfo: .unknown)
        let t0 = Date()
        for _ in 0..<50 { log.error("test", "t.fail", "boom") }
        #expect(Date().timeIntervalSince(t0) < 1.0)
        log.flush(); chmod(dir.path, 0o755)
        #expect(log.failedWrites > 0)
    }
    @Test func debugLevelIsTemporaryAndInMemory() throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(fileURL: root.appendingPathComponent("d.log"), appInfo: .unknown)
        log.debug("t", "dbg.off", "hidden"); log.flush()
        #expect(!FileManager.default.fileExists(atPath: log.fileURL.path))
        log.enableDebug(for: 60); log.debug("t", "dbg.on", "shown"); log.flush()
        #expect(try String(contentsOf: log.fileURL, encoding: .utf8).contains("dbg.on"))
        log.disableDebug(); #expect(!log.debugEnabled)
    }
    @Test func exportIsAValidZipWithOnlyWhitelistedContent() throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let st = StorageLocations.rooted(at: root.appendingPathComponent("app")); try st.createDirectories()
        let log = DiagnosticLog(fileURL: st.logFile, appInfo: AppInfo(version: "1.0", build: "1"))
        log.info("scan", "scan.done", "opened /Users/someone/Movies/ClientX/clip.mov password=hunter2")
        // data that must never travel: media, credentials, licence files next to the app data
        try Data("MEDIA".utf8).write(to: st.appSupport.appendingPathComponent("clip.mov"))
        try Data("secret".utf8).write(to: st.appSupport.appendingPathComponent("license.key"))
        let out = root.appendingPathComponent("out")
        let sum = try DiagnosticsExporter(log: log, storage: st, appInfo: AppInfo(version: "1.0", build: "1"), homePath: "/Users/someone").export(to: out)
        #expect(!sum.includesPaths)
        #expect(sum.files.contains("manifest.json")); #expect(sum.files.contains { $0.hasPrefix("logs/") })
        #expect(!sum.files.contains { $0.hasSuffix(".mov") || $0.hasSuffix(".key") })
        // Validate with the system unzip.
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-p", sum.url.path, "logs/GDCEffectsLibrary.log"]
        let pipe = Pipe(); p.standardOutput = pipe; try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("hunter2")); #expect(!text.contains("ClientX")); #expect(!text.contains("someone"))
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); t.arguments = ["-tq", sum.url.path]
        t.standardOutput = Pipe(); try t.run(); t.waitUntilExit(); #expect(t.terminationStatus == 0)
    }
    @Test func crc32KnownVector() { #expect(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF43926) }
}
