// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Mounts the downloaded disk image read-only, finds the single app, and replaces the target bundle with rollback.
public enum UpdateInstaller {
    public struct Mounted { public let mountPoint: URL; public let app: URL }

    /// Mounts read-only and not browsable; the system chooses the mount point (read from the plist output), so no deprecated or
    /// permission-sensitive `-mountpoint` option is needed.
    public static func mount(_ dmg: URL, at _: URL? = nil) -> Result<Mounted, UpdateFailure> {
        let r = Tool.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-plist", dmg.path])
        guard r.status == 0, let d = r.out.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
              let ents = plist["system-entities"] as? [[String: Any]],
              let mp = ents.compactMap({ $0["mount-point"] as? String }).first
        else { return .failure(.notAnAppImage("could not open the disk image: " + String(r.err.prefix(160)))) }
        let mountPoint = URL(fileURLWithPath: mp, isDirectory: true)
        let apps = ((try? FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first else { unmount(mountPoint); return .failure(.notAnAppImage("expected exactly one app, found \(apps.count)")) }
        return .success(Mounted(mountPoint: mountPoint, app: app))
    }
    public static func unmount(_ mountPoint: URL) {
        if Tool.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"]).status != 0 { _ = Tool.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"]) }
    }

    /// The running copy can be updated only if it lives in a normal writable location (not a mounted image, not translocated).
    public static func checkInstallable(_ target: URL) -> UpdateFailure? {
        let p = target.resolvingSymlinksInPath().path
        if p.contains("/AppTranslocation/") { return .notInstallable("the app is running from a temporary location; move it to Applications and open it from there") }
        if p.hasPrefix("/Volumes/"), (try? target.deletingLastPathComponent().resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true { return .notInstallable("the app is running from a read-only disk image; copy it to Applications first") }
        if !FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) { return .notInstallable("the folder \(target.deletingLastPathComponent().lastPathComponent) is not writable for your account; download the new version and replace the app yourself") }
        return nil
    }

    /// Copy next to the target, swap by renames, verify, remove the backup. Any failure restores the previous bundle.
    public static func replace(target: URL, with newApp: URL, verifyInstalled: (URL) -> UpdateFailure?) -> Result<Void, UpdateFailure> {
        let fm = FileManager.default; let dir = target.deletingLastPathComponent(); let id = UUID().uuidString.prefix(8)
        let staged = dir.appendingPathComponent(".ScanerGDC-update-\(id).app"), backup = dir.appendingPathComponent(".ScanerGDC-previous-\(id).app")
        let c = Tool.run("/usr/bin/ditto", [newApp.path, staged.path])
        guard c.status == 0 else { try? fm.removeItem(at: staged); return .failure(.installFailed("copy failed", rolledBack: false)) }
        if let f = verifyInstalled(staged) { try? fm.removeItem(at: staged); return .failure(f) }
        do { try fm.moveItem(at: target, to: backup) } catch { try? fm.removeItem(at: staged); return .failure(.installFailed("could not set the old version aside", rolledBack: false)) }
        do { try fm.moveItem(at: staged, to: target) }
        catch { let rb = (try? fm.moveItem(at: backup, to: target)) != nil; try? fm.removeItem(at: staged); return .failure(.installFailed("could not put the new version in place", rolledBack: rb)) }
        if let f = verifyInstalled(target) {
            try? fm.removeItem(at: target); let rb = (try? fm.moveItem(at: backup, to: target)) != nil
            if case .installFailed(let m, _) = f { return .failure(.installFailed(m, rolledBack: rb)) }
            return .failure(.installFailed(f.description, rolledBack: rb))
        }
        try? fm.removeItem(at: backup)
        return .success(())
    }

    /// Reopens the app after THIS process exits (detached; waits for the old process to end first).
    public static func relaunch(app: URL, afterExitOf pid: Int32) {
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open -n \"$1\""
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", script, "sh", app.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        try? p.run()
    }
}
