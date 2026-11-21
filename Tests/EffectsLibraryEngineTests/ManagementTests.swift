// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Testing
import Foundation
import EffectsLibraryCore
@testable import EffectsLibraryEngine
import EffectsLibraryTestSupport

struct DifferentVolume: VolumeProbe { func sameVolume(_ a: URL, _ b: URL) -> Bool { false } }
struct FakeHosts: RunningHostProbe { func runningHosts() -> [String] { ["DaVinci Resolve"] } }

private struct Rig {
    let root: URL, plugins: URL, source: SourceDescriptor, journal: OperationJournal
    init() throws {
        root = try SyntheticFixtures.workRoot()
        plugins = root.appendingPathComponent("Plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        source = SourceDescriptor(id: "src", displayName: "Plugins", url: plugins, kinds: [.ofx], origin: .custom)
        journal = OperationJournal(url: root.appendingPathComponent("operations.jsonl"))
    }
    func make(_ name: String = "Alpha", bundleID: String = "dev.test.alpha") throws -> (URL, EffectItem) {
        let u = try SyntheticFixtures.bundle(.ofx, name: name, in: plugins, bundleID: bundleID)
        return (u, EffectItem(name: name, kind: .ofx, sourceID: "src", path: u.path, bundleIdentifier: bundleID))
    }
    func engine(_ v: VolumeProbe = SystemVolumeProbe(), hosts: RunningHostProbe = NoHostProbe()) -> ManagementEngine {
        ManagementEngine(journal: journal, volumes: v, hosts: hosts)
    }
    func disabledItem(_ plan: OperationPlan) -> EffectItem {
        EffectItem(name: plan.itemName, kind: .ofx, sourceID: "src", path: plan.to.path, bundleIdentifier: "dev.test.alpha", state: .disabled)
    }
}

@Suite struct ManagementTests {
    let fm = FileManager.default

    @Test func disableAndRestoreSameVolume() async throws {
        let r = try Rig(); let (u, item) = try r.make(); let e = r.engine()
        let plan = await e.planDisable(item, sources: [r.source])
        #expect(plan.isAllowed); #expect(plan.sameVolume)
        #expect(!plan.to.path.hasPrefix(r.plugins.path + "/"))            // never inside the scanned root
        let out = try await e.execute(plan, confirmation: Confirmation(planID: plan.id))
        #expect(out.state == .completed)
        #expect(!fm.fileExists(atPath: u.path)); #expect(fm.fileExists(atPath: plan.to.path))
        #expect(r.journal.latestPerOperation().last?.phase == .completed)
        let rp = await e.planRestore(r.disabledItem(plan), sources: [r.source])
        #expect(rp.isAllowed); #expect(rp.to.path == u.path)
        _ = try await e.execute(rp, confirmation: Confirmation(planID: rp.id))
        #expect(fm.fileExists(atPath: u.path)); #expect(!fm.fileExists(atPath: plan.to.path))
    }

    @Test func requiresMatchingConfirmation() async throws {
        let r = try Rig(); let (u, item) = try r.make(); let e = r.engine()
        let plan = await e.planDisable(item, sources: [r.source])
        await #expect(throws: ManagementError.self) { try await e.execute(plan, confirmation: nil) }
        await #expect(throws: ManagementError.self) { try await e.execute(plan, confirmation: Confirmation(planID: "other")) }
        #expect(fm.fileExists(atPath: u.path))
    }

    @Test func collisionIsBlockedAndNothingOverwritten() async throws {
        let r = try Rig(); let (u, item) = try r.make(); let e = r.engine()
        let first = await e.planDisable(item, sources: [r.source])
        try fm.createDirectory(at: first.to, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: first.to.appendingPathComponent("marker"))
        let plan = await e.planDisable(item, sources: [r.source])
        #expect(!plan.isAllowed)
        await #expect(throws: ManagementError.self) { try await e.execute(plan, confirmation: Confirmation(planID: plan.id)) }
        #expect(fm.fileExists(atPath: u.path))
        #expect(try Data(contentsOf: first.to.appendingPathComponent("marker")) == Data("keep".utf8))
    }

    @Test func driftAfterPreflightAborts() async throws {
        let r = try Rig(); let (u, item) = try r.make(); let e = r.engine()
        let plan = await e.planDisable(item, sources: [r.source])
        try Data("changed".utf8).write(to: u.appendingPathComponent("Contents/Resources/extra.txt"))
        await #expect(throws: ManagementError.self) { try await e.execute(plan, confirmation: Confirmation(planID: plan.id)) }
        #expect(fm.fileExists(atPath: u.path))
    }

    @Test func unwritableLocationIsBlocked() async throws {
        let r = try Rig(); let (_, item) = try r.make(); let e = r.engine()
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: r.plugins.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: r.plugins.path) }
        let plan = await e.planDisable(item, sources: [r.source])
        #expect(!plan.isAllowed); #expect(plan.blockers.contains { $0.contains("permission") })
    }

    @Test func symlinkItemIsBlocked() async throws {
        let r = try Rig(); let (u, _) = try r.make()
        let link = r.plugins.appendingPathComponent("Link.ofx.bundle")
        try fm.createSymbolicLink(at: link, withDestinationURL: u)
        let item = EffectItem(name: "Link", kind: .ofx, sourceID: "src", path: link.path)
        let plan = await r.engine().planDisable(item, sources: [r.source])
        #expect(!plan.isAllowed)
    }

    @Test func identityMismatchIsBlocked() async throws {
        let r = try Rig(); let (u, _) = try r.make()
        let item = EffectItem(name: "Alpha", kind: .ofx, sourceID: "src", path: u.path, bundleIdentifier: "dev.test.OTHER")
        let plan = await r.engine().planDisable(item, sources: [r.source])
        #expect(!plan.isAllowed)
    }

    @Test func runningHostIsAWarningNotABlocker() async throws {
        let r = try Rig(); let (_, item) = try r.make()
        let plan = await r.engine(hosts: FakeHosts()).planDisable(item, sources: [r.source])
        #expect(plan.isAllowed); #expect(plan.warnings.contains { $0.contains("DaVinci Resolve") })
    }

    @Test func crossVolumeCopyVerifiesAndPreservesMetadata() async throws {
        let r = try Rig(); let (u, item) = try r.make()
        // symlink inside the bundle + extended attribute (quarantine) must survive
        try fm.createSymbolicLink(atPath: u.appendingPathComponent("Contents/Resources/lnk").path, withDestinationPath: "MacOS")
        let q = "0083;00000000;Safari;"
        _ = u.appendingPathComponent("Contents/Info.plist").path.withCString { p in q.withCString { v in setxattr(p, "com.apple.quarantine", v, strlen(v), 0, 0) } }
        let e = r.engine(DifferentVolume())
        let plan = await e.planDisable(item, sources: [r.source])
        #expect(!plan.sameVolume); #expect(plan.warnings.contains { $0.contains("another volume") })
        let out = try await e.execute(plan, confirmation: Confirmation(planID: plan.id))
        #expect(out.state == .completed)
        #expect(!fm.fileExists(atPath: u.path)); #expect(fm.fileExists(atPath: plan.to.path))
        let dst = plan.to
        let target = try fm.destinationOfSymbolicLink(atPath: dst.appendingPathComponent("Contents/Resources/lnk").path)
        #expect(target == "MacOS")
        var buf = [CChar](repeating: 0, count: 64)
        let n = getxattr(dst.appendingPathComponent("Contents/Info.plist").path, "com.apple.quarantine", &buf, 64, 0, 0)
        #expect(n > 0); #expect(String(cString: buf) == q)
        let leftovers = try fm.contentsOfDirectory(atPath: dst.deletingLastPathComponent().path).filter { $0.hasPrefix(".gdc-partial") }
        #expect(leftovers.isEmpty)
    }

    @Test(arguments: ["beforeRename", "afterRename"]) func sameVolumeInterruptionRecovers(point: String) async throws {
        let r = try Rig(); let (u, item) = try r.make(); let e = r.engine()
        let plan = await e.planDisable(item, sources: [r.source])
        await e.setFaultHook { if $0 == point { throw SimulatedCrash() } }
        await #expect(throws: SimulatedCrash.self) { try await e.execute(plan, confirmation: Confirmation(planID: plan.id)) }
        #expect(r.journal.incomplete().count == 1)
        await e.setFaultHook(nil)
        let rep = await e.recoverInterrupted()
        #expect(rep.count == 1); #expect(r.journal.incomplete().isEmpty)
        let exactlyOne = fm.fileExists(atPath: u.path) != fm.fileExists(atPath: plan.to.path)
        #expect(exactlyOne)                                                 // never lost, never duplicated
        #expect(fm.fileExists(atPath: plan.to.path) == (point == "afterRename"))
    }

    @Test(arguments: ["beforeCopy", "afterCopy", "afterVerify", "afterCommit"]) func crossVolumeInterruptionRecovers(point: String) async throws {
        let r = try Rig(); let (u, item) = try r.make(); let e = r.engine(DifferentVolume())
        let plan = await e.planDisable(item, sources: [r.source])
        await e.setFaultHook { if $0 == point { throw SimulatedCrash() } }
        await #expect(throws: SimulatedCrash.self) { try await e.execute(plan, confirmation: Confirmation(planID: plan.id)) }
        await e.setFaultHook(nil)
        _ = await e.recoverInterrupted()
        #expect(r.journal.incomplete().isEmpty)
        let parent = plan.to.deletingLastPathComponent()
        let partials = ((try? fm.contentsOfDirectory(atPath: parent.path)) ?? []).filter { $0.hasPrefix(".gdc-partial") }
        #expect(partials.isEmpty)                                           // own partial copies cleaned up
        // never lose the item: it exists in at least one place (original, destination, or Trash)
        let committed = point == "afterCommit"
        #expect(fm.fileExists(atPath: plan.to.path) == committed)
        #expect(fm.fileExists(atPath: u.path) == !committed)
    }

    @Test func restoreDoesNotOverwriteExistingOriginal() async throws {
        let r = try Rig(); let (u, item) = try r.make(); let e = r.engine()
        let plan = await e.planDisable(item, sources: [r.source])
        _ = try await e.execute(plan, confirmation: Confirmation(planID: plan.id))
        try fm.createDirectory(at: u, withIntermediateDirectories: true)    // something else took the spot
        let rp = await e.planRestore(r.disabledItem(plan), sources: [r.source])
        #expect(!rp.isAllowed)
        #expect(fm.fileExists(atPath: plan.to.path))
    }
}

@Suite struct AssemblerTests {
    @Test func disabledStoresAreScannedAndLinkedToTheirSource() async throws {
        let r = try Rig(); let (u, item) = try r.make(); let e = r.engine()
        let plan = await e.planDisable(item, sources: [r.source])
        _ = try await e.execute(plan, confirmation: Confirmation(planID: plan.id))
        let descs = InventoryAssembler.descriptors(standard: [r.source], custom: [], disabledOverride: nil)
        #expect(descs.count == 2); #expect(descs[1].disabledOf == "src")
        let summary = await LibraryScanner().scanAll(descs)
        let inv = InventoryAssembler.assemble(summary.results, journal: r.journal)
        #expect(inv.items.count == 1)
        #expect(inv.items[0].state == .disabled); #expect(inv.items[0].originalPath == u.path)
        #expect(inv.sources.contains { $0.parentSourceID == "src" })
    }
}

/// Runs only when `GEL_XVOL` points at a second mounted volume (scripts/test-crossvolume.sh).
@Suite struct CrossVolumeRealTests {
    @Test func disableToAnotherVolumeAndBack() async throws {
        guard let xv = ProcessInfo.processInfo.environment["GEL_XVOL"] else { return }
        let r = try Rig(); let (u, item) = try r.make()
        let e = r.engine()
        let override = URL(fileURLWithPath: xv).appendingPathComponent("disabled", isDirectory: true)
        let plan = await e.planDisable(item, sources: [r.source], disabledOverride: override)
        #expect(!plan.sameVolume); #expect(plan.isAllowed)
        let out = try await e.execute(plan, confirmation: Confirmation(planID: plan.id))
        #expect(out.state == .completed)
        #expect(!FileManager.default.fileExists(atPath: u.path)); #expect(FileManager.default.fileExists(atPath: plan.to.path))
        let rp = await e.planRestore(EffectItem(name: "Alpha", kind: .ofx, sourceID: "src", path: plan.to.path, bundleIdentifier: "dev.test.alpha", state: .disabled), sources: [r.source])
        #expect(rp.isAllowed)
        _ = try await e.execute(rp, confirmation: Confirmation(planID: rp.id))
        #expect(FileManager.default.fileExists(atPath: u.path))
    }
}
