// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore

// MARK: Plan / preflight

public struct PreflightIssue: Sendable, Equatable {
    public enum Severity: Sendable { case blocker, warning }
    public var severity: Severity
    public var message: String
}

public struct OperationPlan: Sendable, Identifiable {
    public let id: String
    public var kind: OperationKind
    public var itemID: String
    public var itemName: String
    public var from: URL
    public var to: URL
    public var originalPath: String
    public var sameVolume: Bool
    public var bytes: Int64
    public var issues: [PreflightIssue]
    public var manifestDigest: String?
    public var isAllowed: Bool { !issues.contains { $0.severity == .blocker } }
    public var blockers: [String] { issues.filter { $0.severity == .blocker }.map(\.message) }
    public var warnings: [String] { issues.filter { $0.severity == .warning }.map(\.message) }
}

/// Created only by an explicit in-app confirmation for one specific plan.
public struct Confirmation: Sendable { public let planID: String; public init(planID: String) { self.planID = planID } }

public enum OperationState: String, Sendable { case completed, completedOriginalKept }
public struct OperationOutcome: Sendable { public var opID: String; public var state: OperationState; public var from: URL; public var to: URL; public var message: String }

public enum ManagementError: Error, CustomStringConvertible {
    case notConfirmed, blocked([String]), changedSincePreflight([String]), collision(String), failed(String)
    public var description: String {
        switch self {
        case .notConfirmed: "The operation was not confirmed."
        case .blocked(let b): "Blocked: " + b.joined(separator: " ")
        case .changedSincePreflight(let d): "The item changed after the preflight check (\(d.joined(separator: ", "))). Nothing was moved; run the check again."
        case .collision(let p): "Something already exists at the destination (\(p)); it was not overwritten."
        case .failed(let m): m
        }
    }
}

public struct SimulatedCrash: Error {}

public protocol VolumeProbe: Sendable { func sameVolume(_ a: URL, _ b: URL) -> Bool }
public struct SystemVolumeProbe: VolumeProbe {
    public init() {}
    public func sameVolume(_ a: URL, _ b: URL) -> Bool {
        func vol(_ u: URL) -> String? {
            var url = u
            while !FileManager.default.fileExists(atPath: url.path), url.path != "/" { url = url.deletingLastPathComponent() }
            var st = stat(); return stat(url.path, &st) == 0 ? String(st.st_dev) : nil
        }
        return vol(a) != nil && vol(a) == vol(b)
    }
}
/// Names of host apps that may have plugins loaded. The app never closes them.
public protocol RunningHostProbe: Sendable { func runningHosts() -> [String] }
public struct NoHostProbe: RunningHostProbe { public init() {}; public func runningHosts() -> [String] { [] } }

public enum DisabledLocations {
    /// Default: a sibling folder next to the source root, on the same volume (hosts do not scan it).
    /// With an override (possibly on another volume): `override/<sourceID>`.
    public static func root(for source: SourceDescriptor, override: URL?) -> URL {
        if let override { return override.appendingPathComponent(source.id, isDirectory: true) }
        return source.url.deletingLastPathComponent().appendingPathComponent(source.url.lastPathComponent + " (Disabled by GDC)", isDirectory: true)
    }
}

// MARK: Engine

public actor ManagementEngine {
    public static let knownHostBundleNames = ["DaVinci Resolve", "Logic Pro", "Final Cut Pro", "Ableton Live", "Premiere Pro", "Pro Tools", "GarageBand"]
    private let journal: OperationJournal
    private let log: DiagnosticLog?
    private let volumes: VolumeProbe
    private let hosts: RunningHostProbe
    /// Test hook: called at named points; throwing `SimulatedCrash` aborts without any cleanup (like a killed process).
    public var faultHook: (@Sendable (String) throws -> Void)?
    public func setFaultHook(_ h: (@Sendable (String) throws -> Void)?) { faultHook = h }

    public init(journal: OperationJournal, log: DiagnosticLog? = nil, volumes: VolumeProbe = SystemVolumeProbe(), hosts: RunningHostProbe = NoHostProbe()) {
        self.journal = journal; self.log = log; self.volumes = volumes; self.hosts = hosts
    }

    private let fm = FileManager.default

    // MARK: Preflight

    public func planDisable(_ item: EffectItem, sources: [SourceDescriptor], disabledOverride: URL? = nil) -> OperationPlan {
        var issues: [PreflightIssue] = []
        let from = URL(fileURLWithPath: item.path)
        let src = sources.first { $0.id == item.sourceID }
        func block(_ m: String) { issues.append(.init(severity: .blocker, message: m)) }
        func warn(_ m: String) { issues.append(.init(severity: .warning, message: m)) }
        if item.state == .disabled { block("The item is already disabled.") }
        guard let src else {
            block("The source of this item is unknown."); return plan(.disable, item, from, from, from.path, true, 0, issues, nil)
        }
        let dest = DisabledLocations.root(for: src, override: disabledOverride).appendingPathComponent(from.lastPathComponent)
        issues += commonChecks(item: item, from: from, to: dest, sources: sources, kind: .disable, warn: warn, block: block)
        return finishPlan(.disable, item, from, dest, original: from.path, issues: issues)
    }

    public func planRestore(_ item: EffectItem, sources: [SourceDescriptor]) -> OperationPlan {
        var issues: [PreflightIssue] = []
        let from = URL(fileURLWithPath: item.path)
        func block(_ m: String) { issues.append(.init(severity: .blocker, message: m)) }
        func warn(_ m: String) { issues.append(.init(severity: .warning, message: m)) }
        if item.state != .disabled { block("The item is not disabled.") }
        var original: String? = journal.disabledRecord(atPath: from.path)?.originalPath
        if original == nil, let rec = Self.readSidecar(for: from) { original = rec; warn("The journal has no record; the original location was read from the folder's restore note.") }
        if original == nil, let parent = sources.first(where: { $0.id == item.sourceID })?.url {
            original = parent.appendingPathComponent(from.lastPathComponent).path
            warn("No record of the original location; restoring into the source folder: \(parent.path).")
        }
        guard let original else { block("The original location is unknown."); return plan(.restore, item, from, from, from.path, true, 0, issues, nil) }
        let to = URL(fileURLWithPath: original)
        // identity: the disabled copy should be what was disabled
        if let rec = journal.disabledRecord(atPath: from.path), let dg = rec.manifestDigest, let m = try? TreeManifest.build(at: from, withContents: false), m.digest != dg {
            warn("The item has changed since it was disabled (it may have been updated or modified).")
        }
        issues += commonChecks(item: item, from: from, to: to, sources: sources, kind: .restore, warn: warn, block: block)
        return finishPlan(.restore, item, from, to, original: original, issues: issues)
    }

    private func commonChecks(item: EffectItem, from: URL, to: URL, sources: [SourceDescriptor], kind: OperationKind,
                              warn: (String) -> Void, block: (String) -> Void) -> [PreflightIssue] {
        var extra: [PreflightIssue] = []
        var st = stat()
        guard lstat(from.path, &st) == 0 else { block("The item no longer exists at \(from.path). Refresh the inventory."); return [] }
        if (st.st_mode & S_IFMT) == S_IFLNK { block("The item is a symbolic link; moving links is not supported.") }
        if st.st_flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE) | UInt32(SF_RESTRICTED)) != 0 { block("The item is locked or protected by the system.") }
        if let b = item.bundleIdentifier, (st.st_mode & S_IFMT) == S_IFDIR {
            let pl = try? PropertyListSerialization.propertyList(from: Data(contentsOf: from.appendingPathComponent("Contents/Info.plist")), options: [], format: nil) as? [String: Any]
            if let id = pl?["CFBundleIdentifier"] as? String, id != b { block("The bundle at this path is a different product than the one listed (\(id)). Refresh the inventory.") }
        }
        if let mod = item.modified, let cur = try? from.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, abs(cur.timeIntervalSince(mod)) > 1 {
            warn("The item changed since the last scan.")
        }
        // permissions: must be able to take it out of its folder and put it into the destination folder
        if !fm.isWritableFile(atPath: from.deletingLastPathComponent().path) {
            block("No permission to modify \(from.deletingLastPathComponent().path). This version has no privileged helper; use a folder you own or change permissions yourself.")
        }
        let existingAncestor = nearestExisting(to.deletingLastPathComponent())
        if !fm.isWritableFile(atPath: existingAncestor.path) { block("No permission to write in \(existingAncestor.path).") }
        // collision: never overwrite
        if (try? to.checkResourceIsReachable()) == true || lstat(to.path, &st) == 0 {
            block("Something already exists at the destination (\(to.path)). It will not be overwritten.")
        }
        // the disabled store must not sit inside an active scan root (hosts could still load it)
        if kind == .disable, let own = sources.first(where: { $0.id == item.sourceID }) {
            for s in sources where s.disabledOf == nil && to.standardizedFileURL.path.hasPrefix(s.canonicalPath + "/") {
                block("The disabled folder would be inside the scanned folder \(s.displayName); hosts could still load it.")
            }
            _ = own
        }
        let same = volumes.sameVolume(from, to)
        if !same {
            warn("The destination is on another volume: the item will be copied, verified byte-for-byte, then the original moved to the Trash.")
        }
        let running = hosts.runningHosts()
        if !running.isEmpty { warn("\(running.joined(separator: ", ")) is running and may have this plugin loaded. Changes take effect after you restart it; the app will not close it.") }
        _ = extra; extra = []
        return extra
    }

    private func nearestExisting(_ u: URL) -> URL { var x = u; while !fm.fileExists(atPath: x.path), x.path != "/" { x = x.deletingLastPathComponent() }; return x }

    private func plan(_ kind: OperationKind, _ item: EffectItem, _ from: URL, _ to: URL, _ original: String, _ same: Bool, _ bytes: Int64, _ issues: [PreflightIssue], _ digest: String?) -> OperationPlan {
        OperationPlan(id: Correlation.newID("op"), kind: kind, itemID: item.id, itemName: item.name, from: from, to: to, originalPath: original, sameVolume: same, bytes: bytes, issues: issues, manifestDigest: digest)
    }

    private func finishPlan(_ kind: OperationKind, _ item: EffectItem, _ from: URL, _ to: URL, original: String, issues: [PreflightIssue]) -> OperationPlan {
        var issues = issues
        let same = volumes.sameVolume(from, to)
        var digest: String?, bytes: Int64 = 0
        if !issues.contains(where: { $0.severity == .blocker }) {
            do { let m = try TreeManifest.build(at: from, withContents: false); digest = m.digest; bytes = m.totalBytes
                if !same { // free space on the destination volume
                    let anc = nearestExisting(to.deletingLastPathComponent())
                    let rv = try? anc.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
                    let avail = max(rv?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(rv?.volumeAvailableCapacity ?? 0))
                    let need = bytes + bytes / 10 + 10_000_000
                    if avail < need { issues.append(.init(severity: .blocker, message: "Not enough free space on the destination volume (needs about \(ByteCountFormatter.string(fromByteCount: need, countStyle: .file)))." )) }
                }
            } catch { issues.append(.init(severity: .blocker, message: "The item cannot be read completely: \(error)")) }
        }
        return plan(kind, item, from, to, original, same, bytes, issues, digest)
    }

    // MARK: Execute

    public func execute(_ plan: OperationPlan, confirmation: Confirmation?) throws -> OperationOutcome {
        guard let confirmation, confirmation.planID == plan.id else { throw ManagementError.notConfirmed }
        guard plan.isAllowed else { throw ManagementError.blocked(plan.blockers) }
        return try Correlation.$id.withValue(plan.id) { try run(plan) }
    }

    private func jr(_ p: OperationPlan, _ phase: OperationPhase, _ msg: String = "") throws {
        try journal.append(p.id, p.kind, phase, itemID: p.itemID, itemName: p.itemName, from: p.from.path, to: p.to.path, sameVolume: p.sameVolume,
                           originalPath: p.originalPath, digest: p.manifestDigest, message: msg)
    }

    private func run(_ p: OperationPlan) throws -> OperationOutcome {
        log?.info("management", "op.start", "\(p.kind.rawValue) \(p.itemName) sameVolume=\(p.sameVolume)", fields: ["op": p.id])
        try jr(p, .planned)
        // identity re-check right before touching anything
        if let d = p.manifestDigest {
            let now = try TreeManifest.build(at: p.from, withContents: false)
            if now.digest != d { try jr(p, .aborted, "item changed after preflight"); throw ManagementError.changedSincePreflight(["content or structure differs"]) }
        }
        do {
            let outcome = p.sameVolume ? try moveSameVolume(p) : try moveCrossVolume(p)
            return outcome
        } catch is SimulatedCrash {
            throw SimulatedCrash()                        // no cleanup, no journal: emulates a killed process
        } catch {
            try? jr(p, .failed, "\(error)")
            log?.error("management", "op.failed", "\(p.itemName): \(error)", fields: ["op": p.id])
            throw error
        }
    }

    private func prepareDestination(_ p: OperationPlan) throws {
        try fm.createDirectory(at: p.to.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func moveSameVolume(_ p: OperationPlan) throws -> OperationOutcome {
        try prepareDestination(p)
        try jr(p, .started)
        try faultHook?("beforeRename")
        // renamex_np(RENAME_EXCL): atomic, and fails instead of overwriting if the destination appeared meanwhile.
        if renamex_np(p.from.path, p.to.path, UInt32(RENAME_EXCL)) != 0 {
            let e = errno
            try jr(p, .aborted, "rename failed errno \(e)")
            throw e == EEXIST ? ManagementError.collision(p.to.path) : ManagementError.failed("The move failed (\(String(cString: strerror(e)))).")
        }
        try faultHook?("afterRename")
        try finalize(p, message: "renamed on the same volume")
        return OperationOutcome(opID: p.id, state: .completed, from: p.from, to: p.to, message: "Moved on the same volume.")
    }

    private func moveCrossVolume(_ p: OperationPlan) throws -> OperationOutcome {
        try prepareDestination(p)
        let partial = p.to.deletingLastPathComponent().appendingPathComponent(".gdc-partial-\(p.id)-\(p.to.lastPathComponent)")
        try jr(p, .started)
        try jr(p, .copying, "partial: \(partial.lastPathComponent)")
        try faultHook?("beforeCopy")
        do { try fm.copyItem(at: p.from, to: partial) }       // copies symlinks as links and extended attributes as-is
        catch { try? fm.removeItem(at: partial); try jr(p, .aborted, "copy failed: \(error.localizedDescription)"); throw ManagementError.failed("Copy failed: \(error.localizedDescription)") }
        try faultHook?("afterCopy")
        // verify byte-for-byte (content hashes, symlink targets, xattrs) before anything is committed
        let src = try TreeManifest.build(at: p.from, withContents: true), dst = try TreeManifest.build(at: partial, withContents: true)
        let diff = dst.differences(from: src)
        guard diff.isEmpty else {
            try? fm.removeItem(at: partial); try jr(p, .aborted, "verification failed: \(diff.joined(separator: "; "))")
            throw ManagementError.failed("The copy did not match the original (\(diff.joined(separator: ", "))). The original was left untouched.")
        }
        try jr(p, .verified, "digest \(src.digest.prefix(12))")
        try faultHook?("afterVerify")
        if renamex_np(partial.path, p.to.path, UInt32(RENAME_EXCL)) != 0 {
            let e = errno; try? fm.removeItem(at: partial); try jr(p, .aborted, "commit rename failed errno \(e)")
            throw e == EEXIST ? ManagementError.collision(p.to.path) : ManagementError.failed("Could not finalize the copy.")
        }
        try jr(p, .committed)
        try faultHook?("afterCommit")
        return try removeOriginalAndFinish(p)
    }

    private func removeOriginalAndFinish(_ p: OperationPlan) throws -> OperationOutcome {
        do { try fm.trashItem(at: p.from, resultingItemURL: nil) }
        catch {
            try finalize(p, message: "copied; original NOT removed (\(error.localizedDescription))")
            return OperationOutcome(opID: p.id, state: .completedOriginalKept, from: p.from, to: p.to,
                                    message: "The copy is in place, but the original could not be moved to the Trash (\(error.localizedDescription)). Remove it manually.")
        }
        try jr(p, .trashedSource)
        try faultHook?("afterTrash")
        try finalize(p, message: "copied, verified, original moved to Trash")
        return OperationOutcome(opID: p.id, state: .completed, from: p.from, to: p.to, message: "Copied and verified across volumes; the original is in the Trash.")
    }

    private func finalize(_ p: OperationPlan, message: String) throws {
        if p.kind == .disable { Self.writeSidecar(for: p.to, original: p.originalPath, opID: p.id) }
        else { Self.removeSidecar(for: p.from) }
        try jr(p, .completed, message)
        log?.info("management", "op.completed", "\(p.kind.rawValue) \(p.itemName)", fields: ["op": p.id])
    }

    // MARK: Recovery after an interruption

    public struct RecoveryReport: Sendable { public var opID: String; public var itemName: String; public var action: String }

    /// Resolves operations left unfinished (crash, kill, power loss). Never deletes anything but its own partial copies.
    public func recoverInterrupted() -> [RecoveryReport] {
        var reports: [RecoveryReport] = []
        for e in journal.incomplete() {
            let from = URL(fileURLWithPath: e.from), to = URL(fileURLWithPath: e.to)
            var stF = stat(), stT = stat()
            let fromExists = lstat(from.path, &stF) == 0, toExists = lstat(to.path, &stT) == 0
            func rec(_ phase: OperationPhase, _ msg: String) {
                _ = try? journal.append(e.opID, e.kind, phase, itemID: e.itemID, itemName: e.itemName, from: e.from, to: e.to, sameVolume: e.sameVolume, originalPath: e.originalPath, digest: e.manifestDigest, message: "recovery: " + msg)
                reports.append(.init(opID: e.opID, itemName: e.itemName, action: msg))
                log?.warning("management", "op.recovered", "\(e.itemName): \(msg)", fields: ["op": e.opID, "phase": e.phase.rawValue])
            }
            // remove only partial copies that belong to this operation
            let partials = ((try? fm.contentsOfDirectory(atPath: to.deletingLastPathComponent().path)) ?? []).filter { $0.hasPrefix(".gdc-partial-\(e.opID)-") }
            switch (fromExists, toExists) {
            case (true, false):
                for p in partials { try? fm.removeItem(at: to.deletingLastPathComponent().appendingPathComponent(p)) }
                rec(.aborted, "interrupted before the item was moved; the original is untouched\(partials.isEmpty ? "" : " (partial copy removed)")")
            case (false, true):
                let plan = OperationPlan(id: e.opID, kind: e.kind, itemID: e.itemID, itemName: e.itemName, from: from, to: to, originalPath: e.originalPath ?? e.from, sameVolume: e.sameVolume, bytes: 0, issues: [], manifestDigest: e.manifestDigest)
                if e.kind == .disable { Self.writeSidecar(for: to, original: plan.originalPath, opID: e.opID) } else { Self.removeSidecar(for: from) }
                rec(.completed, "the move had completed; journal brought up to date")
            case (true, true):
                if e.phase == .committed || e.phase == .verified, !e.sameVolume {
                    // verify the destination really equals the original before removing the original
                    if let a = try? TreeManifest.build(at: from, withContents: true), let b = try? TreeManifest.build(at: to, withContents: true), b.differences(from: a).isEmpty {
                        if (try? fm.trashItem(at: from, resultingItemURL: nil)) != nil {
                            if e.kind == .disable { Self.writeSidecar(for: to, original: e.originalPath ?? e.from, opID: e.opID) } else { Self.removeSidecar(for: from) }
                            rec(.completed, "copy verified identical; original moved to the Trash")
                        } else { rec(.failed, "copy is in place; original could not be moved to the Trash — remove it manually") }
                    } else { rec(.failed, "both copies exist and differ; nothing was deleted — inspect both") }
                } else {
                    for p in partials { try? fm.removeItem(at: to.deletingLastPathComponent().appendingPathComponent(p)) }
                    rec(.failed, "both locations exist; nothing was deleted — inspect both")
                }
            case (false, false):
                rec(.failed, "the item is missing from both locations; check the Trash")
            }
        }
        return reports
    }

    // MARK: Restore notes (redundant record inside the disabled folder)

    static func sidecarURL(for disabled: URL) -> URL {
        disabled.deletingLastPathComponent().appendingPathComponent(".gdc-restore", isDirectory: true).appendingPathComponent(disabled.lastPathComponent + ".json")
    }
    static func writeSidecar(for disabled: URL, original: String, opID: String) {
        let u = sidecarURL(for: disabled)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let d = try? JSONSerialization.data(withJSONObject: ["originalPath": original, "operation": opID, "note": "Written by Scaner GDC; used to restore this item."], options: [.sortedKeys, .withoutEscapingSlashes])
        try? d?.write(to: u, options: .atomic)
    }
    static func readSidecar(for disabled: URL) -> String? {
        guard let d = try? Data(contentsOf: sidecarURL(for: disabled)), let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return nil }
        return o["originalPath"]
    }
    static func removeSidecar(for disabled: URL) { try? FileManager.default.removeItem(at: sidecarURL(for: disabled)) }
}
