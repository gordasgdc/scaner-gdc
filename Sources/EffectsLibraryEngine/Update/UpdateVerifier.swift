// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import CryptoKit

/// Runs a system tool and captures output (used for codesign, stapler, hdiutil). Never uses a shell string.
enum Tool {
    struct Output { let status: Int32; let out: String; let err: String }
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 120) -> Output {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
        do { try p.run() } catch { return Output(status: -1, out: "", err: "\(error)") }
        let deadline = Date().addingTimeInterval(timeout)
        final class Box: @unchecked Sendable { var d = Data() }
        let ob = Box(), eb = Box()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { ob.d = o.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { eb.d = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate() }
        g.wait(); p.waitUntilExit()
        return Output(status: p.terminationStatus, out: String(decoding: ob.d, as: UTF8.self), err: String(decoding: eb.d, as: UTF8.self))
    }
}

public enum UpdateVerifier {
    public static func sha256(of file: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: file); defer { try? h.close() }
        var hasher = SHA256()
        while let d = try h.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(data: d) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Authenticates a downloaded app bundle. The manifest is NOT the trust anchor: the bundle must carry the pinned bundle id and be signed
    /// by the pinned Apple Developer Team ID with a valid, strict, deep signature (and a stapled notarization ticket when required).
    /// A version must be newer than the installed one and equal to the announced one.
    public static func verifyApp(_ app: URL, config: UpdateConfig, installedVersion: String, expectedVersion: String) -> Result<String, UpdateFailure> {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let bid = info["CFBundleIdentifier"] as? String, let ver = info["CFBundleShortVersionString"] as? String
        else { return .failure(.notAnAppImage("no readable Info.plist")) }
        guard bid == config.bundleIdentifier else { return .failure(.identity("bundle id \(bid)")) }
        let v = Tool.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard v.status == 0 else { return .failure(.signature(firstLine(v.err))) }
        let d = Tool.run("/usr/bin/codesign", ["-dv", "--verbose=4", app.path])
        let text = d.err + d.out
        let team = text.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }.map { String($0.dropFirst("TeamIdentifier=".count)) }
        guard team == config.teamIdentifier else { return .failure(.identity("team \(team ?? "none")")) }
        guard text.contains("Authority=Developer ID Application") else { return .failure(.identity("not a Developer ID signature")) }
        if config.requireStapledTicket {
            let s = Tool.run("/usr/bin/xcrun", ["stapler", "validate", app.path])
            guard s.status == 0 else { return .failure(.signature("no valid notarization ticket")) }
        }
        guard let new = SemVer.parse(ver), let cur = SemVer.parse(installedVersion), let exp = SemVer.parse(expectedVersion) else { return .failure(.invalidManifest("version format")) }
        guard SemVer.compare(new.core, exp.core) == 0 else { return .failure(.versionMismatch(expected: expectedVersion, found: ver)) }
        guard SemVer.compare(new.core, cur.core) > 0 else { return .failure(.notNewer(installed: installedVersion, offered: ver)) }
        return .success(ver)
    }
    static func firstLine(_ s: String) -> String { String(s.split(separator: "\n").first ?? "unknown").prefix(160).description }
}
