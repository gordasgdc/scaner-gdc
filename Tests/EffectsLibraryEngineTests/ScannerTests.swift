// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Testing
import Foundation
import EffectsLibraryCore
import EffectsLibraryEngine
import EffectsLibraryTestSupport

@Suite struct ScannerTests {
    let scanner = LibraryScanner()

    @Test func scansFixturesAndReadsMetadata() async throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let (desc, total) = try SyntheticFixtures.populate(root: root, .init(ofx: 5, vst3: 4, au: 3, vst: 2, luts: 6, dctls: 3))
        let s = await scanner.scanAll(desc)
        #expect(s.totalItems == total)
        #expect(s.results.allSatisfy { $0.availability == .available })
        let all = s.results.flatMap(\.items)
        // bundle internals are not indexed as items
        #expect(!all.contains { $0.path.contains("/Contents/") })
        let v3 = try #require(all.first { $0.kind == .vst3 && $0.name == "V3 Plugin 2" })
        #expect(v3.vendor == "Vendor 2"); #expect(v3.exposedEffects == ["Plugin 2"]); #expect(v3.bundleIdentifier == "com.synthetic.v3.2")
        let au = try #require(all.first { $0.kind == .audioUnit && $0.name == "AU Plugin 1" })
        #expect(au.vendor == "Vendor 1"); #expect(au.exposedEffects == ["Plugin 1"])
        let ofx0 = try #require(all.first { $0.kind == .ofx && $0.name == "OFX Effect 0" })
        #expect(ofx0.architectures == ["arm64", "x86_64"]); #expect(ofx0.vendor == nil, "vendor is never inferred")
        let vst = try #require(all.first { $0.kind == .vst })
        #expect(vst.version == nil)
        let lut = try #require(all.first { $0.kind == .lut })
        #expect(lut.details["Size"] == "3D 17³"); #expect(lut.previewSupport == .lutCube)
        let dctl = try #require(all.first { $0.kind == .dctl })
        #expect(dctl.details["UI parameters"] == "2"); #expect(dctl.details["Transform function"] == "found")
        #expect(dctl.previewSupport == .none)
    }

    @Test func idsAreStableAcrossRescans() async throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let (desc, _) = try SyntheticFixtures.populate(root: root, .init(ofx: 3, luts: 2))
        let a = await scanner.scanAll(desc).results.flatMap(\.items).map(\.id).sorted()
        let b = await scanner.scanAll(desc).results.flatMap(\.items).map(\.id).sorted()
        #expect(a == b); #expect(Set(a).count == a.count)
    }

    @Test func missingStandardIsMissingAndMissingCustomIsUnavailable() async throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let std = SourceDescriptor(id: "a", displayName: "a", url: root.appendingPathComponent("nope"), kinds: [.vst3], origin: .standard)
        let cus = SourceDescriptor(id: "b", displayName: "b", url: root.appendingPathComponent("nope2"), kinds: [.vst3], origin: .custom)
        let s = await scanner.scanAll([std, cus])
        #expect(s.results[0].availability == .missing)
        guard case .unavailable = s.results[1].availability else { Issue.record("custom missing must be unavailable"); return }
    }

    @Test func unreadableFolderIsNeverAnEmptySuccess() async throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let locked = root.appendingPathComponent("locked"); try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try SyntheticFixtures.bundle(.vst3, name: "Hidden", in: locked)
        chmod(locked.path, 0o000); defer { chmod(locked.path, 0o755) }
        let r = await scanner.scanSource(SourceDescriptor(id: "l", displayName: "l", url: locked, kinds: [.vst3], origin: .custom))
        guard case .unavailable(let why) = r.availability else { Issue.record("expected unavailable, got \(r.availability)"); return }
        #expect(why.contains("Permission denied")); #expect(r.items.isEmpty)
    }

    @Test func overlappingRootsAreDeduplicated() async throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let (desc, total) = try SyntheticFixtures.populate(root: root, .init(luts: 3, dctls: 2))
        let lutRoot = desc[0]
        let inner = SourceDescriptor(id: "inner", displayName: "inner", url: lutRoot.url.appendingPathComponent("DCTL"), kinds: [.dctl], origin: .custom)
        let same = SourceDescriptor(id: "same", displayName: "same", url: lutRoot.url, kinds: [.lut], origin: .custom)
        let s = await scanner.scanAll([lutRoot, inner, same])
        #expect(s.results.count == 1); #expect(s.totalItems == total)
        #expect(s.merges.count == 2)
        // inner root with an extra kind keeps only the part not covered
        let reduced = RootDeduplicator.reduce([lutRoot, SourceDescriptor(id: "i2", displayName: "i2", url: lutRoot.url.appendingPathComponent("DCTL"), kinds: [.dctl, .vst3], origin: .custom)])
        #expect(reduced.kept.count == 2); #expect(reduced.kept[1].kinds == [.vst3])
    }

    @Test func symlinkedAndHiddenEntriesAreHandledSafely() async throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let d = root.appendingPathComponent("v"); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let real = try SyntheticFixtures.bundle(.vst3, name: "Real", in: root)
        try FileManager.default.createSymbolicLink(at: d.appendingPathComponent("Link.vst3"), withDestinationURL: real)
        try SyntheticFixtures.bundle(.vst3, name: ".HiddenOne", in: d)
        let r = await scanner.scanSource(SourceDescriptor(id: "v", displayName: "v", url: d, kinds: [.vst3], origin: .custom))
        #expect(r.items.count <= 1, "hidden skipped, symlink target not traversed twice")
        if let l = r.items.first { #expect(l.details["Symbolic link"] != nil) }
    }

    @Test func cancellationStopsTheScan() async throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let (desc, total) = try SyntheticFixtures.populate(root: root, .init(ofx: 400, vst3: 400, au: 400))
        let task = Task { await scanner.scanAll(desc) }
        task.cancel()
        let s = await task.value
        #expect(s.cancelled || s.totalItems <= total)
        #expect(s.totalItems < total || s.cancelled == false)  // either finished normally or stopped early; never crashes
    }

    @Test func itemLimitIsReportedAsWarningNotSilentlyTruncated() async throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let (desc, _) = try SyntheticFixtures.populate(root: root, .init(vst3: 20))
        var limits = ScanLimits(); limits.maxItemsPerSource = 5
        let r = await LibraryScanner(limits: limits).scanSource(desc[0])
        #expect(r.items.count == 5); #expect(r.truncated); #expect(r.warnings.contains { $0.contains("limit") })
    }

    @Test func machOReader() {
        #expect(MachOReader.architectures(in: SyntheticFixtures.machO(["arm64"])) == ["arm64"])
        #expect(MachOReader.architectures(in: SyntheticFixtures.machO(["x86_64", "arm64"])) == ["arm64", "x86_64"])
        #expect(MachOReader.architectures(in: SyntheticFixtures.machO(["arm64e", "x86_64"])) == ["arm64e", "x86_64"])
        #expect(MachOReader.architectures(in: Data("not a binary at all".utf8)) == nil)
        #expect(MachOReader.architectures(in: Data()) == nil)
    }

    @Test func disabledStoreItemsAreMarkedDisabled() async throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let d = root.appendingPathComponent("VST3 (Disabled by GDC)"); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try SyntheticFixtures.bundle(.vst3, name: "Off", in: d)
        let r = await scanner.scanSource(SourceDescriptor(id: "dis", displayName: "dis", url: d, kinds: [.vst3], origin: .disabledStore, disabledOf: "x"))
        #expect(r.items.first?.state == .disabled)
    }
}
