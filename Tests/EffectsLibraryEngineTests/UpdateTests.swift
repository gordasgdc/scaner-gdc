// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Testing
import Foundation
@testable import EffectsLibraryEngine

private struct ManifestFetcher: HTTPFetcher {
    let reply: Result<Data, FetchError>
    func fetch(_ url: URL, limits: FetchLimits) async throws -> FetchResult { FetchResult(data: try reply.get(), finalURL: url, contentType: "application/json") }
}
private final class FileDownloader: HTTPDownloader, @unchecked Sendable {
    let data: Data?; let error: FetchError?; private(set) var calls = 0
    init(data: Data? = nil, error: FetchError? = nil) { self.data = data; self.error = error }
    func download(_ url: URL, maxBytes: Int64, timeout: TimeInterval, to file: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws {
        calls += 1; if let error { throw error }; try data!.write(to: file); progress(Int64(data!.count), Int64(data!.count))
    }
}
private let prefix = "https://github.com/gordasgdc/scaner-gdc/releases/download/"
private func manifest(_ v: String, url: String? = nil, extra: String = "") -> Data {
    Data("{\"version\":\"\(v)\",\"build\":\"9\",\"changes\":\"Notes\",\"mandatory\":false,\"download_url\":\"\(url ?? prefix + "v\(v)/ScanerGDC-macOS-\(v).dmg")\"\(extra)}".utf8)
}
private func service(_ r: Result<Data, FetchError>, installed: String = "0.6.0", dl: FileDownloader = FileDownloader(), os: OperatingSystemVersion = .init(majorVersion: 15, minorVersion: 0, patchVersion: 0)) -> UpdateService {
    UpdateService(fetcher: ManifestFetcher(reply: r), downloader: dl, installedVersion: installed, osVersion: { os })
}

@Suite struct UpdateCheckTests {
    @Test func offersOnlyNewerStableVersions() async {
        if case .available(let o) = await service(.success(manifest("0.6.1"))).check() { #expect(o.version == "0.6.1"); #expect(o.changes == "Notes") } else { Issue.record("expected available") }
        if case .upToDate = await service(.success(manifest("0.6.0"))).check() {} else { Issue.record("equal must be up to date") }
        if case .upToDate = await service(.success(manifest("0.5.9"))).check() {} else { Issue.record("older must never be offered (no downgrade)") }
        #expect(await service(.success(manifest("0.7.0-beta.1"))).check() == .failed(.prerelease("0.7.0-beta.1")))
    }
    @Test func distinctFailuresAreNotUpToDate() async {
        #expect(await service(.failure(.offline)).check() == .failed(.offline))
        #expect(await service(.failure(.timeout)).check() == .failed(.timeout))
        #expect(await service(.failure(.http(503))).check() == .failed(.http(503)))
        if case .failed(.invalidManifest) = await service(.success(Data("nope".utf8))).check() {} else { Issue.record("invalid manifest") }
        if case .failed(.invalidManifest) = await service(.success(manifest("banana"))).check() {} else { Issue.record("bad version") }
    }
    @Test func untrustedDownloadAddressesAreRefused() async {
        for u in ["https://evil.example/x.dmg", "http://github.com/gordasgdc/scaner-gdc/releases/download/v9/x.dmg", "https://github.com/other/repo/releases/download/v9/x.dmg", "file:///tmp/x.dmg"] {
            #expect(await service(.success(manifest("0.9.0", url: u))).check() == .failed(.untrustedDownloadURL), "\(u)")
        }
    }
    @Test func tolerantManifestFieldsAndOSRequirement() async {
        let dict = Data("{\"version\":\"0.7.0\",\"download_url\":{\"mac\":\"\(prefix)v0.7.0/a.dmg\"},\"future_field\":1}".utf8)
        if case .available = await service(.success(dict)).check() {} else { Issue.record("dict download_url + unknown fields") }
        #expect(await service(.success(manifest("0.7.0", extra: ",\"min_os\":\"16.0\""))).check() == .failed(.osTooOld("16.0")))
    }
    @Test func versionComparisonAndInstalledNeverReplacedByCheck() {
        #expect(SemVer.compare([0, 10, 0], [0, 9, 9]) == 1); #expect(SemVer.compare([1, 0], [1, 0, 0]) == 0); #expect(SemVer.parse("v1.2.3")?.core == [1, 2, 3]); #expect(SemVer.parse("1.2.x") == nil)
    }
}

@Suite struct UpdateInstallTests {
    private func tmp() -> URL { let u = FileManager.default.temporaryDirectory.appendingPathComponent("gel-upd-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u }
    private func fakeApp(_ dir: URL, name: String = "Scaner GDC.app", version: String, bundle: String = "dev.gordas.GDCEffectsLibrary") -> URL {
        let app = dir.appendingPathComponent(name); let c = app.appendingPathComponent("Contents"); try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundle, "CFBundleShortVersionString": version]
        (plist as NSDictionary).write(to: c.appendingPathComponent("Info.plist"), atomically: true); return app
    }
    private func dmg(containing app: URL, in dir: URL) -> Data {
        let src = dir.appendingPathComponent("src-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: app, to: src.appendingPathComponent(app.lastPathComponent))
        let out = dir.appendingPathComponent("t-\(UUID().uuidString).dmg")
        _ = Tool.run("/usr/bin/hdiutil", ["create", "-quiet", "-srcfolder", src.path, "-format", "UDZO", out.path])
        return (try? Data(contentsOf: out)) ?? Data()
    }
    private func offer(_ v: String, sha: String? = nil) -> UpdateOffer { UpdateOffer(version: v, changes: "", downloadURL: URL(string: prefix + "v\(v)/a.dmg")!, sha256: sha, size: 1_000_000, mandatory: false) }

    @Test func replaceSwapsAndRollsBackOnFailure() {
        let d = tmp(); let target = fakeApp(d, version: "0.6.0"); let new = fakeApp(tmp(), version: "0.6.1")
        let ok = UpdateInstaller.replace(target: target, with: new) { _ in nil }
        if case .success = ok {} else { Issue.record("swap should succeed") }
        #expect((NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleShortVersionString"] as? String == "0.6.1")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []; #expect(left == ["Scaner GDC.app"])      // no stray backups
        // failure after the swap: previous version is restored
        let d2 = tmp(); let t2 = fakeApp(d2, version: "0.6.0"); var calls = 0
        let bad = UpdateInstaller.replace(target: t2, with: fakeApp(tmp(), version: "0.6.1")) { app in calls += 1; return app.lastPathComponent == "Scaner GDC.app" ? .signature("boom") : nil }
        if case .failure(.installFailed(_, let rb)) = bad { #expect(rb) } else { Issue.record("expected rollback failure") }
        #expect((NSDictionary(contentsOf: t2.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleShortVersionString"] as? String == "0.6.0")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: d2.path)) ?? []).count == 1)
    }
    @Test func unsignedOrWrongIdentityPackagesNeverInstall() async {
        let w = tmp(); let target = fakeApp(w, version: "0.6.0")
        let data = dmg(containing: fakeApp(tmp(), version: "0.6.1"), in: tmp())
        let dl = FileDownloader(data: data)
        let svc = service(.success(Data()), dl: dl)
        let r = await svc.install(offer("0.6.1"), target: target, workDir: tmp(), relaunch: false) { _ in }
        if case .failure(.signature) = r {} else { Issue.record("unsigned bundle must fail signature: \(r)") }
        #expect((NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleShortVersionString"] as? String == "0.6.0")
        let wrongID = dmg(containing: fakeApp(tmp(), version: "0.6.1", bundle: "com.evil.app"), in: tmp())
        let r2 = await service(.success(Data()), dl: FileDownloader(data: wrongID)).install(offer("0.6.1"), target: target, workDir: tmp(), relaunch: false) { _ in }
        if case .failure(.identity) = r2 {} else { Issue.record("wrong bundle id must fail identity: \(r2)") }
    }
    @Test func checksumDownloadErrorsAndCancellation() async {
        let w = tmp(); let target = fakeApp(w, version: "0.6.0")
        let r = await service(.success(Data()), dl: FileDownloader(data: Data("abc".utf8))).install(offer("0.6.1", sha: String(repeating: "0", count: 64)), target: target, workDir: tmp(), relaunch: false) { _ in }
        #expect(r == .failure(.checksumMismatch))
        #expect(await service(.success(Data()), dl: FileDownloader(error: .offline)).install(offer("0.6.1"), target: target, workDir: tmp(), relaunch: false) { _ in } == .failure(.offline))
        #expect(await service(.success(Data()), dl: FileDownloader(error: .cancelled)).install(offer("0.6.1"), target: target, workDir: tmp(), relaunch: false) { _ in } == .failure(.cancelled))
        let big = UpdateOffer(version: "9.0.0", changes: "", downloadURL: URL(string: prefix + "v9/a.dmg")!, sha256: nil, size: Int64.max / 8, mandatory: false)
        let dl = FileDownloader(data: Data())
        if case .failure(.diskSpace) = await service(.success(Data()), dl: dl).install(big, target: target, workDir: tmp(), relaunch: false, phase: { _ in }) {} else { Issue.record("expected disk space failure") }
        #expect(dl.calls == 0)      // nothing downloaded when space is insufficient
    }
    @Test func nonInstallableLocationsAreExplained() {
        #expect(UpdateInstaller.checkInstallable(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Scaner GDC.app")) != nil)
        #expect(UpdateInstaller.checkInstallable(URL(fileURLWithPath: "/System/Applications/Scaner GDC.app")) != nil)
        #expect(UpdateInstaller.checkInstallable(fakeApp(tmp(), version: "0.6.0")) == nil)
    }
}
