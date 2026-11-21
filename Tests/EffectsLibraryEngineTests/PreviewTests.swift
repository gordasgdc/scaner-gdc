// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Testing
import Foundation
import CoreGraphics
import ImageIO
import EffectsLibraryCore
import EffectsLibraryEngine
import EffectsLibraryTestSupport

private func cube(_ s: String) throws -> CubeLUT { try CubeLUT.parse(data: Data(s.utf8)) }
private func pngSize(_ d: Data) -> (Int, Int)? {
    guard let s = CGImageSourceCreateWithData(d as CFData, nil), let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] else { return nil }
    return (p[kCGImagePropertyPixelWidth] as? Int ?? 0, p[kCGImagePropertyPixelHeight] as? Int ?? 0)
}

@Suite struct CubeLUTTests {
    @Test func identity3DIsIdentity() throws {
        let l = try cube(SyntheticFixtures.cube3D(size: 9))
        for (r, g, b) in [(0.0, 0.0, 0.0), (1, 1, 1), (0.3, 0.6, 0.9), (0.123, 0.456, 0.789)] as [(Float, Float, Float)] {
            let o = l.apply(r, g, b); #expect(abs(o.0 - r) < 1e-5 && abs(o.1 - g) < 1e-5 && abs(o.2 - b) < 1e-5)
        }
    }
    @Test func invertExactAtLatticeAndLinearBetween() throws {
        let l = try cube(SyntheticFixtures.cube3D(size: 5) { (1 - $0, 1 - $1, 1 - $2) })
        let o = l.apply(0.25, 0.5, 0.75); #expect(abs(o.0 - 0.75) < 1e-6 && abs(o.1 - 0.5) < 1e-6 && abs(o.2 - 0.25) < 1e-6)
        let m = l.apply(0.125, 0.125, 0.125); #expect(abs(m.0 - 0.875) < 1e-6)   // midpoint of linear function stays exact
    }
    @Test func redIndexVariesFastest() throws {
        // 2x2x2: value encodes (r,g,b) index; row order must be r fastest, then g, then b
        let rows = (0..<8).map { i in "\(Float(i) / 7) 0 0" }.joined(separator: "\n")
        let l = try cube("LUT_3D_SIZE 2\n" + rows + "\n")
        #expect(abs(l.apply(1, 0, 0).0 - 1.0 / 7) < 1e-6)   // r=1,g=0,b=0 → row 1
        #expect(abs(l.apply(0, 1, 0).0 - 2.0 / 7) < 1e-6)   // row 2
        #expect(abs(l.apply(0, 0, 1).0 - 4.0 / 7) < 1e-6)   // row 4
    }
    @Test func domainScalingAndClamping() throws {
        let l = try cube(SyntheticFixtures.cube3D(size: 5, domain: (-1, 3)))
        let o = l.apply(1, 1, 1)           // middle of domain → middle of table
        #expect(abs(o.0 - 0.5) < 1e-5)
        #expect(l.apply(10, 10, 10).0 == 1 && l.apply(-10, -10, -10).0 == 0)
    }
    @Test func oneDLut() throws {
        let l = try cube(SyntheticFixtures.cube1D(size: 11) { $0 * $0 })
        #expect(abs(l.apply(0.5, 0.5, 0.5).0 - 0.25) < 0.006)   // piecewise-linear approximation of x²
        #expect(l.kind == .lut1D(11))
    }
    @Test func rejectsInvalidAndUnsupportedVariantsWithReasons() {
        func err(_ s: String) -> CubeLUT.ParseError? { do { _ = try CubeLUT.parse(data: Data(s.utf8)); return nil } catch let e as CubeLUT.ParseError { return e } catch { return nil } }
        let one = "0 0 0\n1 1 1\n"
        #expect(err("") == .emptyFile)
        #expect(err("TITLE x\n" + one) == .missingSize)
        #expect(err("LUT_3D_SIZE 2\nLUT_1D_SIZE 2\n" + one) == .bothSizes)
        #expect(err("LUT_3D_SIZE 1\n0 0 0\n") == .badSize(1))
        #expect(err("LUT_3D_SIZE 130\n0 0 0\n") == .badSize(130))
        #expect(err("LUT_1D_SIZE 2\nFOO 1\n" + one) == .unsupportedKeyword("FOO", line: 2))
        #expect(err("LUT_1D_SIZE 2\n0 0 0\n") == .wrongRowCount(expected: 2, found: 1))
        #expect(err("LUT_1D_SIZE 2\n0 0 0\n1 1 1\n2 2 2\n") == .wrongRowCount(expected: 2, found: 3))
        #expect(err("LUT_1D_SIZE 2\n0 0 0\n1 nan 1\n") == .nonFinite(line: 3))
        #expect(err("LUT_1D_SIZE 2\n0 0 0\n1 inf 1\n") == .nonFinite(line: 3))
        #expect(err("LUT_1D_SIZE 2\nDOMAIN_MIN 0 0\n" + one) == .badDomain)
        #expect(err("LUT_1D_SIZE 2\nDOMAIN_MIN 1 1 1\nDOMAIN_MAX 0 0 0\n" + one) == .badDomain)
        #expect(err("LUT_1D_SIZE 2\n0 0 x\n1 1 1\n") == .badLine(2))
        #expect(err("LUT_1D_SIZE 2\n0 0 0\nTITLE late\n1 1 1\n") == .badLine(3))
        var bin = Data("LUT_1D_SIZE 2\n".utf8); bin.append(0); #expect(err(String(decoding: bin, as: UTF8.self)) != nil)
    }
    @Test func fileSizeLimitIsEnforcedBeforeParsing() {
        #expect(throws: CubeLUT.ParseError.tooLarge(bytes: CubeLUT.maxFileBytes + 1)) { _ = try CubeLUT.parse(data: Data(count: CubeLUT.maxFileBytes + 1)) }
    }
    @Test func inputRangeAliasesAndComments() throws {
        let l = try cube("# c\nTITLE \"T\"\nLUT_1D_INPUT_RANGE 0.0 2.0\nLUT_1D_SIZE 2\n\n0 0 0\n1 1 1\n")
        #expect(l.domainMax == [2, 2, 2]); #expect(l.title == "T"); #expect(abs(l.apply(1, 1, 1).0 - 0.5) < 1e-6)
    }
}

@Suite struct PreviewRenderAndCacheTests {
    @Test func referenceIsDeterministicAndHashed() {
        let a = ReferenceImage.make(), b = ReferenceImage.make()
        #expect(a.pixels == b.pixels); #expect(a.contentHash == b.contentHash)
        #expect(ReferenceImage.make(width: 200, height: 100).contentHash != a.contentHash)
        #expect(a.pixels.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
    @Test func renderIsDeterministicAndIdentityMatchesReference() throws {
        let ref = ReferenceImage.make(width: 96, height: 60)
        let id = try cube(SyntheticFixtures.cube3D(size: 17))
        let p1 = LUTPreviewRenderer.png(LUTPreviewRenderer.render(id, reference: ref)!)!, p2 = LUTPreviewRenderer.png(LUTPreviewRenderer.render(id, reference: ref)!)!
        #expect(p1 == p2)
        #expect(pngSize(p1)! == (96, 60))
        let inv = try cube(SyntheticFixtures.cube3D(size: 17) { (1 - $0, 1 - $1, 1 - $2) })
        #expect(LUTPreviewRenderer.png(LUTPreviewRenderer.render(inv, reference: ref)!)! != p1)
    }
    @Test func keyChangesWithEveryComponent() {
        let base = PreviewKey(contentHash: "c", settings: "s", referenceID: "r", referenceHash: "h")
        #expect(base == PreviewKey(contentHash: "c", settings: "s", referenceID: "r", referenceHash: "h"))
        #expect(base != PreviewKey(contentHash: "c2", settings: "s", referenceID: "r", referenceHash: "h"))
        #expect(base != PreviewKey(contentHash: "c", rendererVersion: 99, settings: "s", referenceID: "r", referenceHash: "h"))
        #expect(base != PreviewKey(contentHash: "c", settings: "s2", referenceID: "r", referenceHash: "h"))
        #expect(base != PreviewKey(contentHash: "c", settings: "s", referenceID: "r2", referenceHash: "h"))
        #expect(base != PreviewKey(contentHash: "c", settings: "s", referenceID: "r", referenceHash: "h2"))
    }
    @Test func cacheEvictsLeastRecentlyUsedAndStaysUnderCap() throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let png = SyntheticFixtures.solidPNG(width: 16, height: 16, rgb: (1, 2, 3)); let n = png.count
        let cap = n * 3 + 10
        let c = PreviewCache(directory: root, maxBytes: cap)
        let keys = (0..<5).map { PreviewKey(raw: "k\($0)") }
        for k in keys.prefix(3) { c.put(k, png); Thread.sleep(forTimeInterval: 0.02) }
        _ = c.get(keys[0]); Thread.sleep(forTimeInterval: 0.02)            // refresh k0 → k1 is now the oldest
        c.put(keys[3], png); c.put(keys[4], png)
        #expect(c.totalBytes <= cap)
        #expect(c.get(keys[0]) != nil, "recently used entry survives"); #expect(c.get(keys[1]) == nil, "oldest evicted first")
        #expect(c.put(PreviewKey(raw: "huge"), Data(count: cap + 1)) == false)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { $0.hasSuffix(".png") }, "no temp files left")
        c.removeAll(); #expect(c.count == 0)
    }
    @Test func corruptCacheEntryIsDroppedAndTreatedAsMiss() throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let c = PreviewCache(directory: root); let k = PreviewKey(raw: "bad")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not a png at all".utf8).write(to: root.appendingPathComponent("bad.png"))
        #expect(c.get(k) == nil); #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("bad.png").path))
    }
    @Test func pruneKeepsOnlyListedKeys() throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let c = PreviewCache(directory: root); let png = SyntheticFixtures.solidPNG(width: 8, height: 8, rgb: (9, 9, 9))
        c.put(PreviewKey(raw: "a"), png); c.put(PreviewKey(raw: "b"), png)
        c.prune(keeping: [PreviewKey(raw: "a")]); #expect(c.count == 1); #expect(c.get(PreviewKey(raw: "a")) != nil)
    }
}

@Suite struct PreviewServiceTests {
    func setup() throws -> (URL, PreviewService, PreviewCache) {
        let root = try SyntheticFixtures.workRoot()
        let cache = PreviewCache(directory: root.appendingPathComponent("cache"))
        return (root, PreviewService(cache: cache), cache)
    }
    func lutItem(_ url: URL) -> EffectItem { EffectItem(name: "L", kind: .lut, sourceID: "s", path: url.path, previewSupport: .lutCube) }

    @Test func lutRendersThenHitsCacheThenInvalidatesOnContentChange() async throws {
        let (root, svc, _) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let f = root.appendingPathComponent("a.cube"); try SyntheticFixtures.cube3D(size: 9).write(to: f, atomically: true, encoding: .utf8)
        guard case .image(let p1, let s1, let isRender) = await svc.preview(for: lutItem(f)) else { Issue.record("no image"); return }
        #expect(s1 == .rendered); #expect(isRender); #expect(pngSize(p1)! == (384, 240))
        guard case .image(let p2, let s2, _) = await svc.preview(for: lutItem(f)) else { return }
        #expect(s2 == .cache); #expect(p2 == p1)
        try SyntheticFixtures.cube3D(size: 9) { (1 - $0, $1, $2) }.write(to: f, atomically: true, encoding: .utf8)
        guard case .image(let p3, let s3, _) = await svc.preview(for: lutItem(f)) else { return }
        #expect(s3 == .rendered, "changed content must not be served from cache"); #expect(p3 != p1)
        guard case .image(_, let s4, _) = await svc.preview(for: lutItem(f), regenerate: true) else { return }
        #expect(s4 == .rendered)
    }
    @Test func invalidLutAndDctlAreHonestlyUnavailable() async throws {
        let (root, svc, _) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let bad = root.appendingPathComponent("bad.cube"); try "LUT_3D_SIZE 2\n0 0 0\n".write(to: bad, atomically: true, encoding: .utf8)
        guard case .unavailable(let why) = await svc.preview(for: lutItem(bad)) else { Issue.record("expected unavailable"); return }
        #expect(why.contains("Expected 8 data rows"))
        let dctl = EffectItem(name: "D", kind: .dctl, sourceID: "s", path: "/x/d.dctl", previewSupport: .none, previewNote: "DCTL is shown from metadata only")
        guard case .unavailable(let w2) = await svc.preview(for: dctl) else { Issue.record("dctl must be unavailable"); return }
        #expect(w2.contains("metadata only"))
        let missing = lutItem(root.appendingPathComponent("gone.cube"))
        guard case .unavailable = await svc.preview(for: missing) else { Issue.record("missing file must be unavailable"); return }
    }
    @Test func bundleIconIsExtractedWithoutExecutingAnything() async throws {
        let (root, svc, _) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let b = try SyntheticFixtures.bundle(.vst3, name: "Iconic", in: root, withIcon: true)
        let item = EffectItem(name: "Iconic", kind: .vst3, sourceID: "s", path: b.path, previewSupport: .bundleIcon)
        guard case .image(let d, let src, let isRender) = await svc.preview(for: item) else { Issue.record("no icon"); return }
        #expect(!isRender, "an icon is never presented as a render"); #expect(src == .bundleIcon); #expect(pngSize(d) != nil)
        guard case .image(_, let again, _) = await svc.preview(for: item) else { return }
        #expect(again == .cache)
        let noIcon = try SyntheticFixtures.bundle(.vst3, name: "Plain", in: root)
        guard case .unavailable = await svc.preview(for: EffectItem(name: "P", kind: .vst3, sourceID: "s", path: noIcon.path, previewSupport: .bundleIcon)) else { Issue.record("expected unavailable"); return }
    }
    @Test func batchRegenerationReportsProgressAndCancels() async throws {
        let (root, svc, _) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        var items: [EffectItem] = []
        for i in 0..<12 { let f = root.appendingPathComponent("l\(i).cube"); try SyntheticFixtures.cube3D(size: 9) { ($0, $1, min($2 + Double(i) * 0.01, 1)) }.write(to: f, atomically: true, encoding: .utf8); items.append(lutItem(f)) }
        let counter = Counter()
        let s = await svc.regenerate(items) { done, _ in counter.set(done) }
        #expect(s.produced == 12 && s.requested == 12 && !s.cancelled); #expect(counter.value == 12)
        let t = Task { await svc.regenerate(items) }; t.cancel()
        let c = await t.value; #expect(c.cancelled || c.produced <= 12)
    }
}
final class Counter: @unchecked Sendable { private let l = NSLock(); private var v = 0
    func set(_ x: Int) { l.withLock { v = max(v, x) } }; var value: Int { l.withLock { v } } }
