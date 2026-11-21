// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

public enum UpdatePhase: Sendable, Equatable { case downloading(Int64, Int64?), verifying, installing, done(String) }

/// Check → (user confirms) → download → verify → install. Checking never downloads an app; installing happens only when the caller invokes `install`.
public actor UpdateService {
    private let config: UpdateConfig, fetcher: HTTPFetcher, downloader: HTTPDownloader, log: DiagnosticLog?
    private let installed: String
    private let osVersion: @Sendable () -> OperatingSystemVersion
    public init(config: UpdateConfig = .production, fetcher: HTTPFetcher, downloader: HTTPDownloader, installedVersion: String, log: DiagnosticLog? = nil,
                osVersion: @escaping @Sendable () -> OperatingSystemVersion = { ProcessInfo.processInfo.operatingSystemVersion }) {
        self.config = config; self.fetcher = fetcher; self.downloader = downloader; self.installed = installedVersion; self.log = log; self.osVersion = osVersion
    }

    public func check() async -> UpdateCheckResult {
        var comps = URLComponents(url: config.manifestURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]   // bypass CDN cache; no identifier is sent
        let res: FetchResult
        do { res = try await fetcher.fetch(comps.url!, limits: FetchLimits(maxBytes: 64 * 1024, timeout: 15)) }
        catch FetchError.offline { return .failed(.offline) } catch FetchError.timeout { return .failed(.timeout) }
        catch FetchError.http(let c) { return .failed(.http(c)) } catch FetchError.cancelled { return .failed(.cancelled) }
        catch { return .failed(.other("Could not reach the update server.")) }
        guard let m = try? JSONDecoder().decode(UpdateManifest.self, from: res.data) else { log?.warning("update", "update.manifest.invalid", "undecodable"); return .failed(.invalidManifest("not valid JSON")) }
        guard let pub = SemVer.parse(m.version), let cur = SemVer.parse(installed) else { return .failed(.invalidManifest("version format")) }
        if pub.pre { return .failed(.prerelease(m.version)) }
        guard SemVer.compare(pub.core, cur.core) > 0 else { return .upToDate(installed: installed, published: m.version) }   // never offers an equal or older version
        guard m.downloadURL.hasPrefix(config.downloadPrefix), let url = URL(string: m.downloadURL), case .success = URLPolicy.parse(m.downloadURL) else { return .failed(.untrustedDownloadURL) }
        if let need = m.minOS, let n = SemVer.parse(need) {
            let o = osVersion(); if SemVer.compare(n.core, [o.majorVersion, o.minorVersion, o.patchVersion]) > 0 { return .failed(.osTooOld(need)) }
        }
        return .available(UpdateOffer(version: m.version, changes: String((m.changes ?? "").prefix(2000)), downloadURL: url, sha256: m.sha256?.lowercased(), size: m.size, mandatory: m.mandatory))
    }

    /// Downloads, verifies and replaces `target`. `workDir` must be on a volume with enough space (checked). Cancelling the task leaves everything untouched.
    public func install(_ offer: UpdateOffer, target: URL, workDir: URL, relaunch: Bool, phase: @escaping @Sendable (UpdatePhase) -> Void) async -> Result<String, UpdateFailure> {
        let fm = FileManager.default
        if let f = UpdateInstaller.checkInstallable(target) { return .failure(f) }
        try? fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        let need = (offer.size ?? 60_000_000) * 4
        if let avail = try? workDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, avail < need { return .failure(.diskSpace(needed: need, available: avail)) }
        let id = UUID().uuidString.prefix(8)
        let dmg = workDir.appendingPathComponent("ScanerGDC-update-\(id).dmg"), mnt = workDir.appendingPathComponent("mnt-\(id)")
        defer { try? fm.removeItem(at: dmg); try? fm.removeItem(at: mnt) }
        log?.info("update", "update.download.start", "version=\(offer.version)")
        do { try await downloader.download(offer.downloadURL, maxBytes: 200_000_000, timeout: 20, to: dmg, progress: { phase(.downloading($0, $1)) }) }
        catch FetchError.cancelled { return .failure(.cancelled) } catch FetchError.offline { return .failure(.offline) } catch FetchError.timeout { return .failure(.timeout) }
        catch FetchError.http(let c) { return .failure(.http(c)) } catch let e as FetchError { return .failure(.other(e.description)) } catch { return .failure(.other("Download failed.")) }
        if Task.isCancelled { return .failure(.cancelled) }
        phase(.verifying)
        // The checksum only detects corruption; authenticity comes from the signature check below.
        if let want = offer.sha256, (try? UpdateVerifier.sha256(of: dmg)) != want { return .failure(.checksumMismatch) }
        let mounted: UpdateInstaller.Mounted
        switch UpdateInstaller.mount(dmg) { case .failure(let f): return .failure(f); case .success(let m): mounted = m }
        defer { UpdateInstaller.unmount(mounted.mountPoint) }
        let cfg = config, inst = installed, exp = offer.version
        switch UpdateVerifier.verifyApp(mounted.app, config: cfg, installedVersion: inst, expectedVersion: exp) { case .failure(let f): log?.warning("update", "update.verify.failed", f.description); return .failure(f); case .success: break }
        if Task.isCancelled { return .failure(.cancelled) }
        phase(.installing)
        let r = UpdateInstaller.replace(target: target, with: mounted.app) { app in
            // Re-verify the copy that will actually run (same checks; version must equal the announced one).
            if case .failure(let f) = UpdateVerifier.verifyApp(app, config: cfg, installedVersion: inst, expectedVersion: exp) { return f }
            return nil
        }
        switch r {
        case .failure(let f): log?.warning("update", "update.install.failed", f.description); return .failure(f)
        case .success:
            log?.info("update", "update.install.done", "version=\(offer.version)"); phase(.done(offer.version))
            if relaunch { UpdateInstaller.relaunch(app: target, afterExitOf: ProcessInfo.processInfo.processIdentifier) }
            return .success(offer.version)
        }
    }
}
