// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
@testable import EffectsLibraryEngine
import EffectsLibraryCore

// MARK: helpers (deterministic: no network, no clock)

private func png(_ w: Int, _ h: Int, jpeg: Bool = false) -> Data {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let out = NSMutableData()
    let d = CGImageDestinationCreateWithData(out, (jpeg ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d); return out as Data
}
private func gif2() -> Data {
    let out = NSMutableData(); let d = CGImageDestinationCreateWithData(out, UTType.gif.identifier as CFString, 2, nil)!
    let cs = CGColorSpaceCreateDeviceRGB()
    for _ in 0..<2 { let c = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        CGImageDestinationAddImage(d, c.makeImage()!, nil) }
    CGImageDestinationFinalize(d); return out as Data
}
private func page(_ head: String) -> Data { Data("<html><head>\(head)</head><body>ignored</body></html>".utf8) }

private final class StubFetcher: HTTPFetcher, @unchecked Sendable {
    enum Reply { case ok(Data, String?), fail(FetchError) }
    private let lock = NSLock(); private var replies: [String: Reply]; private(set) var requested: [URL] = []; private(set) var limitsSeen: [FetchLimits] = []
    init(_ r: [String: Reply]) { replies = r }
    func fetch(_ url: URL, limits: FetchLimits) async throws -> FetchResult {
        lock.withLock { requested.append(url); limitsSeen.append(limits) }
        if Task.isCancelled { throw FetchError.cancelled }
        switch lock.withLock({ replies[url.absoluteString] }) {
        case .ok(let d, let ct)?: return FetchResult(data: d, finalURL: url, contentType: ct)
        case .fail(let e)?: throw e
        case nil: throw FetchError.http(404)
        }
    }
    var urls: [String] { lock.withLock { requested.map(\.absoluteString) } }
    var limits: [FetchLimits] { lock.withLock { limitsSeen } }
}
private final class StubSearch: SearchProvider, @unchecked Sendable {
    let result: Result<[SearchCandidate], Error>; private let lock = NSLock(); private(set) var queries: [LookupQuery] = []
    init(_ r: Result<[SearchCandidate], Error>) { result = r }
    func search(_ q: LookupQuery) async throws -> [SearchCandidate] { lock.withLock { queries.append(q) }; return try result.get() }
    var seen: [LookupQuery] { lock.withLock { queries } }
}
private func item(_ name: String = "Acme Glow", vendor: String? = "Acme", bundle: String? = "com.acme.glow", path: String = "/Users/jane.doe/Private Clients/Plug-Ins/Acme Glow.ofx.bundle", effects: [String] = []) -> EffectItem {
    EffectItem(name: name, kind: .ofx, sourceID: "s", path: path, vendor: vendor, version: "3.1.4", bundleIdentifier: bundle, exposedEffects: effects)
}
private func tmpLoc() -> StorageLocations {
    let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()).appendingPathComponent("enr-\(UUID().uuidString)")
    return StorageLocations.rooted(at: base)
}
private let official = "https://acme.example/glow"
private let goodPage = page("<title>Acme Glow</title><meta property='og:site_name' content='Acme'><meta property='og:description' content='A glow effect.'><meta property='og:image' content='/img/cover.png'>")

// MARK: URL policy

@Suite struct URLPolicyTests {
    @Test func acceptsPublicHTTPSOnly() {
        for ok in ["https://acme.example/glow", "https://www.vendor.com/a?b=c", "https://8.8.8.8/x"] { #expect(URLPolicy.parse(ok) == .success(URL(string: ok)!), "\(ok)") }
    }
    @Test func rejectsEverythingElse() {
        let bad = ["http://acme.example", "file:///etc/passwd", "ftp://acme.example", "javascript:alert(1)", "data:text/html,hi", "https://localhost/x", "https://127.0.0.1/",
                   "https://10.1.2.3/", "https://192.168.1.1/", "https://172.16.0.1/", "https://169.254.169.254/latest/meta-data", "https://[::1]/", "https://[fe80::1]/",
                   "https://[::ffff:10.0.0.1]/", "https://user:pw@acme.example/", "https://acme.example:8080/", "https://printer.local/", "https://intranet/", "https://100.64.1.1/",
                   "https://0.0.0.0/", "not a url", "", "https://" + String(repeating: "a", count: 2100) + ".com/"]
        for b in bad { if case .success = URLPolicy.parse(b) { Issue.record("accepted \(b)") } }
    }
    @Test func redirectGuardLimitsAndValidatesEveryHop() {
        var g = RedirectGuard(maxRedirects: 2)
        #expect(g.allow(URL(string: "https://a.example/1")!) == nil)
        #expect(g.allow(URL(string: "http://a.example/2")!) == .blocked(.notHTTPS))
        var g2 = RedirectGuard(maxRedirects: 1)
        #expect(g2.allow(URL(string: "https://a.example/1")!) == nil)
        #expect(g2.allow(URL(string: "https://a.example/2")!) == .tooManyRedirects)
        var g3 = RedirectGuard(maxRedirects: 3)
        #expect(g3.allow(URL(string: "https://192.168.0.5/admin")!) == .blocked(.privateAddress))
    }
    @Test func privateRangesBoundaries() {
        #expect(URLPolicy.literalAddressBlocked("172.15.0.1") == false); #expect(URLPolicy.literalAddressBlocked("172.32.0.1") == false)
        #expect(URLPolicy.literalAddressBlocked("172.31.255.255") == true); #expect(URLPolicy.literalAddressBlocked("100.128.0.1") == false)
        #expect(URLPolicy.literalAddressBlocked("example") == nil)
    }
}

// MARK: images

@Suite struct ImageSanitizerTests {
    @Test func keepsAspectAndDownscales() throws {
        let l = try ImageSanitizer.sanitize(png(2000, 1000)).get(); #expect(l.width == 960 && l.height == 480)
        let p = try ImageSanitizer.sanitize(png(500, 1500)).get(); #expect(p.height == 960 && p.width == 320)
        let small = try ImageSanitizer.sanitize(png(64, 64)).get(); #expect(small.width == 64 && small.height == 64)
        #expect(ImageSanitizer.sniff(l.png) == .png)
    }
    @Test func acceptsJPEGAndReencodesToPNG() throws {
        let c = try ImageSanitizer.sanitize(png(300, 200, jpeg: true)).get(); #expect(ImageSanitizer.sniff(c.png) == .png)
    }
    @Test func rejectsWrongTypesAndBrokenData() {
        #expect(ImageSanitizer.sanitize(Data()) == .failure(.empty))
        #expect(ImageSanitizer.sanitize(Data("<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>".utf8)) == .failure(.unsupportedType))
        #expect(ImageSanitizer.sanitize(Data("<html><body>hi</body></html>".utf8)) == .failure(.unsupportedType))
        #expect(ImageSanitizer.sanitize(Data(repeating: 7, count: 500)) == .failure(.unsupportedType))
        #expect(ImageSanitizer.sanitize(png(100, 100).prefix(40)) == .failure(.undecodable))
        #expect(ImageSanitizer.sanitize(gif2()) == .failure(.animatedOrMultiFrame))
    }
    @Test func rejectsTooLargeBytesAndDimensions() {
        var l = ImageSanitizer.Limits(); l.maxBytes = 100
        #expect(ImageSanitizer.sanitize(png(100, 100), limits: l) == .failure(.tooLarge))
        #expect(ImageSanitizer.sanitize(png(9000, 8)) == .failure(.dimensionsTooLarge))
        var l2 = ImageSanitizer.Limits(); l2.maxPixels = 1000
        #expect(ImageSanitizer.sanitize(png(100, 100), limits: l2) == .failure(.dimensionsTooLarge))
    }
}

extension ImageSanitizer.Clean: Equatable { public static func == (a: Self, b: Self) -> Bool { a.png == b.png } }

// MARK: page text is data

@Suite struct PageMetadataTests {
    let base = URL(string: "https://acme.example/glow")!
    @Test func readsOpenGraphAndResolvesRelativeImage() {
        let m = PageMetadataExtractor.extract(html: goodPage, baseURL: base)
        #expect(m.title == "Acme Glow"); #expect(m.siteName == "Acme"); #expect(m.description == "A glow effect.")
        #expect(m.imageURL?.absoluteString == "https://acme.example/img/cover.png")
    }
    @Test func markupAndScriptsAreInertText() {
        let m = PageMetadataExtractor.extract(html: page("<title>Hi</title><meta name='description' content='&lt;script&gt;alert(1)&lt;/script&gt;Real <b>text</b>&amp; more\u{0007}'>"), baseURL: base)
        #expect(m.description == "Real text& more"); #expect(!(m.description ?? "").contains("<"))
    }
    @Test func lengthCapsAndUnsafeImageAddresses() {
        let long = String(repeating: "x", count: 5000)
        let m = PageMetadataExtractor.extract(html: page("<meta property='og:description' content='\(long)'><meta property='og:image' content='http://acme.example/a.png'>"), baseURL: base)
        #expect((m.description ?? "").count <= 280); #expect(m.imageURL == nil)
        for u in ["file:///etc/passwd", "https://127.0.0.1/a.png", "https://10.0.0.1/a.png", "javascript:alert(1)"] {
            #expect(PageMetadataExtractor.extract(html: page("<meta property='og:image' content='\(u)'>"), baseURL: base).imageURL == nil, "\(u)")
        }
    }
    @Test func canonicalAndTitleFallback() {
        let m = PageMetadataExtractor.extract(html: page("<title>  Acme   Glow | Acme </title><link rel='canonical' href='https://acme.example/glow-2'>"), baseURL: base)
        #expect(m.title == "Acme Glow | Acme"); #expect(m.canonicalURL?.absoluteString == "https://acme.example/glow-2")
    }
}

// MARK: matching

@Suite struct MatcherTests {
    @Test func normalizationKeepsMeaningDropsNoise() {
        #expect(ProductMatcher.normalize("Acme Glow 2.ofx.bundle") == ["acme", "glow"])
        #expect(ProductMatcher.normalize("Glow v3 (Disabled by GDC)") == ["glow"])
        #expect(ProductMatcher.normalize("Éclat Pro VST3") == ["eclat", "pro"])
    }
    @Test func similarNamesAndWrongProducerAreNotStrong() {
        let i = item()
        #expect(ProductMatcher.verdict(item: i, candidateName: "Acme Glow", candidateProducer: "Acme").confidence == .strong)
        #expect(ProductMatcher.verdict(item: i, candidateName: "Acme Glow Pro Bundle", candidateProducer: "Acme").confidence != .strong)
        #expect(ProductMatcher.verdict(item: i, candidateName: "Acme Glow", candidateProducer: "Other Corp").confidence == .ambiguous)
        #expect(ProductMatcher.verdict(item: i, candidateName: "Totally Different", candidateProducer: "Acme").confidence == .weak)
        #expect(ProductMatcher.verdict(item: i, candidateName: nil, candidateProducer: nil).confidence == .weak)
    }
    @Test func suitesAreDistinctFromEffects() {
        #expect(ProductMatcher.isSuite(item(effects: ["A", "B"]))); #expect(!ProductMatcher.isSuite(item(effects: ["A"])))
    }
}

// MARK: service + store

@Suite struct EnrichmentServiceTests {
    fileprivate func make(_ replies: [String: StubFetcher.Reply], search: SearchProvider = NoSearchProvider(), now: Date = Date(timeIntervalSince1970: 1_000_000)) -> (EnrichmentService, EnrichmentStore, StubFetcher, StorageLocations) {
        let loc = tmpLoc(); let st = EnrichmentStore(locations: loc); let f = StubFetcher(replies)
        return (EnrichmentService(store: st, fetcher: f, search: search, now: { now }), st, f, loc)
    }

    @Test func userAssociatedPageIsConfirmedAndNeverTouchesInstalledMetadata() async {
        let (svc, st, f, _) = make([official: .ok(goodPage, "text/html; charset=utf-8")])
        let it = item(); let before = it
        guard case .updated(let r) = await svc.associateOfficialPage(it, address: official) else { Issue.record("not updated"); return }
        #expect(r.status == .confirmed && r.userChoseURL); #expect(r.producer == "Acme"); #expect(r.summary == "A glow effect.")
        #expect(r.proposedImageURL == "https://acme.example/img/cover.png"); #expect(r.cover == nil)   // no image downloaded without acceptance
        #expect(it == before && it.version == "3.1.4")                                                   // installed version untouched
        #expect(f.urls == [official])
        #expect(await st.record(ProductKey.make(for: it))?.officialURL == official)
    }
    @Test func requestsNeverContainPersonalPathsOrFileContents() async {
        let s = StubSearch(.success([SearchCandidate(name: "Acme Glow", producer: "Acme", pageURL: URL(string: official)!)]))
        let (svc, _, f, _) = make([official: .ok(goodPage, "text/html")], search: s)
        _ = await svc.lookup(item(), explicit: true)
        let q = s.seen.first!
        let fields = Mirror(reflecting: q).children.compactMap(\.label).sorted()
        #expect(fields == ["bundleIdentifier", "kind", "name", "producer"])
        let blob = "\(q) \(f.urls)"
        #expect(!blob.contains("/Users/") && !blob.contains("jane.doe") && !blob.contains("Private Clients") && !blob.contains("ofx.bundle"))
    }
    @Test func noSearchServiceMeansSearchUnavailableNotAFakeResult() async {
        let (svc, st, f, _) = make([:]); let it = item()
        #expect(await svc.lookup(it) == .searchUnavailable); #expect(f.urls.isEmpty); #expect(await st.record(ProductKey.make(for: it)) == nil)
    }
    @Test func automaticFindingsAreProposalsAndAmbiguityIsExplained() async {
        let amb = [SearchCandidate(name: "Acme Glow", producer: "Acme", pageURL: URL(string: official)!),
                   SearchCandidate(name: "Acme Glow", producer: "Acme", pageURL: URL(string: "https://acme.example/glow-2")!)]
        let (svc, st, _, _) = make([official: .ok(goodPage, "text/html")], search: StubSearch(.success(amb)))
        guard case .candidates(let c, let amb) = await svc.lookup(item(), explicit: false) else { Issue.record("expected candidates"); return }
        #expect(c.count == 2); #expect(amb)
        #expect(await st.record(ProductKey.make(for: item())) == nil)       // transient: nothing persisted from search results
    }
    @Test func wrongProducerCandidateIsFlaggedAmbiguousAndNothingIsFetchedOrSaved() async {
        let (svc, st, f, _) = make([:],
                                  search: StubSearch(.success([SearchCandidate(name: "Acme Glow", producer: "Other Corp", pageURL: URL(string: "https://other.example/g")!)])))
        guard case .candidates(_, let amb) = await svc.lookup(item(), explicit: false) else { Issue.record("expected candidates"); return }
        #expect(amb); #expect(f.urls.isEmpty); #expect(await st.record(ProductKey.make(for: item())) == nil)
    }
    @Test func nothingFoundIsRememberedTemporarily() async {
        let (svc, st, _, _) = make([:], search: StubSearch(.success([])))
        let it = item()
        if case .notFound = await svc.lookup(it, explicit: false) {} else { Issue.record("expected notFound") }
        let t0 = Date(timeIntervalSince1970: 1_000_000)      // the service's injected clock
        #expect(await st.isRecentlyNotFound(ProductKey.make(for: it), now: t0.addingTimeInterval(60)))
        if case .skipped = await svc.lookup(it, explicit: false) {} else { Issue.record("negative cache not used") }
        #expect(!(await st.isRecentlyNotFound(ProductKey.make(for: it), now: t0.addingTimeInterval(EnrichmentStore.negativeTTL + 5))))
    }
    @Test func offlineTimeoutAndBlockedAreReportedNotCrashed() async {
        let it = item()
        for (e, off) in [(FetchError.offline, true), (.timeout, true), (.http(500), false), (.blocked(.privateAddress), false), (.tooLarge, false)] {
            let (svc, _, _, _) = make([official: .fail(e)])
            guard case .failed(_, let o) = await svc.associateOfficialPage(it, address: official) else { Issue.record("expected failure \(e)"); continue }
            #expect(o == off, "\(e)")
        }
    }
    @Test func invalidAddressesAreRejectedBeforeAnyRequest() async {
        let (svc, st, f, _) = make([:]); let it = item()
        for a in ["http://acme.example", "file:///etc/hosts", "https://127.0.0.1/", "https://intranet/", "garbage"] {
            if case .failed = await svc.associateOfficialPage(it, address: a) {} else { Issue.record("accepted \(a)") }
        }
        #expect(f.urls.isEmpty); #expect(await st.record(ProductKey.make(for: it)) == nil)
    }
    @Test func nonHTMLResponseIsRefused() async {
        let (svc, _, _, _) = make([official: .ok(Data("{}".utf8), "application/json")])
        if case .failed = await svc.associateOfficialPage(item(), address: official) {} else { Issue.record("json accepted") }
    }
    @Test func acceptingTheProposedImageStoresASafeCoverWithProvenance() async throws {
        let (svc, st, f, loc) = make([official: .ok(goodPage, "text/html"), "https://acme.example/img/cover.png": .ok(png(1600, 900), "image/png")])
        let it = item(); _ = await svc.associateOfficialPage(it, address: official)
        guard case .success(let r) = await svc.acceptProposedImage(key: ProductKey.make(for: it)) else { Issue.record("not stored"); return }
        #expect(r.cover?.origin == .officialPage && r.cover?.rights == .pageDeclaredPreview); #expect(r.cover?.sourceURL == "https://acme.example/img/cover.png")
        #expect(r.cover?.pixelWidth == 960 && r.cover?.pixelHeight == 540); #expect(r.proposedImageURL == nil)
        #expect(FileManager.default.fileExists(atPath: loc.fetchedCoversDir.appendingPathComponent(r.cover!.fileName).path))
        #expect(await st.coverData(for: r) != nil); #expect(f.urls.count == 2)
    }
    @Test func invalidOrHostileImagesAreRejectedAndNothingIsStored() async {
        for bad in [Data("<svg><script>1</script></svg>".utf8), Data("<html/>".utf8), png(9000, 8), Data(repeating: 1, count: 100)] {
            let (svc, st, _, loc) = make([official: .ok(goodPage, "text/html"), "https://acme.example/img/cover.png": .ok(bad, "image/png")])
            let it = item(); _ = await svc.associateOfficialPage(it, address: official)
            if case .failure = await svc.acceptProposedImage(key: ProductKey.make(for: it)) {} else { Issue.record("hostile image accepted") }
            #expect(await st.record(ProductKey.make(for: it))?.cover == nil)
            #expect(!FileManager.default.fileExists(atPath: loc.fetchedCoversDir.path) || (try? FileManager.default.contentsOfDirectory(atPath: loc.fetchedCoversDir.path))?.isEmpty == true)
        }
    }
    @Test func manualChoicesAreNeverOverwritten() async {
        let (svc, st, f, _) = make([official: .ok(goodPage, "text/html"), "https://acme.example/img/cover.png": .ok(png(100, 100), "image/png")])
        let it = item(); let key = ProductKey.make(for: it)
        guard case .success(let mine) = await svc.setLocalImage(it, data: png(640, 360)) else { Issue.record("local image failed"); return }
        #expect(mine.userChoseImage && mine.cover?.origin == .userLocal && mine.cover?.rights == .userSupplied)
        _ = await svc.associateOfficialPage(it, address: official)
        #expect(await svc.acceptProposedImage(key: key) == .failure(.nothingProposed))          // no proposal is even offered over a manual image
        let summary = await svc.fill([it])
        #expect(summary.skipped == 1 && summary.completed == 0)
        #expect(await st.record(key)?.cover?.fileName == mine.cover?.fileName)
        _ = f
    }
    @Test func rejectedProposalsStayRejectedInBatchesButCanBeRetriedExplicitly() async {
        let (svc, st, _, _) = make([official: .ok(goodPage, "text/html")], search: StubSearch(.success([SearchCandidate(name: "Acme Glow", producer: "Acme", pageURL: URL(string: official)!)])))
        let it = item(); await st.reject(key: ProductKey.make(for: it))
        let s = await svc.fill([it]); #expect(s.skipped == 1 && s.proposed == 0)
        switch await svc.lookup(it, explicit: true) { case .candidates: break; default: Issue.record("explicit retry should work") }
    }
    @Test func batchSummaryCountsAndHonorsCancellation() async {
        let a = item("Acme Glow", bundle: "com.acme.glow"), b = item("Nope One", vendor: nil, bundle: "x.nope"), c = item("Off Line", vendor: nil, bundle: "x.off")
        let (svc, st, _, _) = make([official: .ok(goodPage, "text/html"), "https://off.example/": .fail(.offline)])
        _ = await st.setOfficialURL(key: ProductKey.make(for: a), url: URL(string: official)!)
        _ = await st.setOfficialURL(key: ProductKey.make(for: c), url: URL(string: "https://off.example/")!)
        let s = await svc.fill([a, b, c])
        #expect(s.requested == 3 && s.manuallyAssociated == 1 && s.completed == 0 && s.searchUnavailable == 1 && s.notFound == 0 && s.network == 1 && s.errors == 0 && s.ambiguous == 0 && !s.cancelled)
        let t = Task { await svc.fill((0..<50).map { item("Item \($0)", bundle: "b.\($0)") }) }
        t.cancel(); let cs = await t.value; #expect(cs.cancelled)
    }
    @Test func progressIsReported() async {
        let (svc, _, _, _) = make([:]); let box = Box()
        _ = await svc.fill([item("A", bundle: "a"), item("B", bundle: "b")]) { d, t in box.set((d, t)) }
        #expect(box.value?.1 == 2 && box.value?.0 == 2)
    }
    final class Box: @unchecked Sendable { private let l = NSLock(); private var v: (Int, Int)?; func set(_ x: (Int, Int)) { l.withLock { v = x } }; var value: (Int, Int)? { l.withLock { v } } }
}

@Suite struct EnrichmentStoreTests {
    @Test func persistsAcrossRelaunchAndSurvivesRescanAndMoves() async throws {
        let loc = tmpLoc(); let it = item()
        let s1 = EnrichmentStore(locations: loc); _ = await s1.setOfficialURL(key: ProductKey.make(for: it), url: URL(string: official)!)
        let moved = item(path: "/Volumes/Other/Disabled/Acme Glow.ofx.bundle")           // same product, new path (Disable/Restore, rescan)
        #expect(ProductKey.make(for: it) == ProductKey.make(for: moved)); #expect(it.id != moved.id)
        let s2 = EnrichmentStore(locations: loc); try await s2.load()
        #expect(await s2.record(ProductKey.make(for: moved))?.officialURL == official)
    }
    @Test func clearingTheCacheKeepsAssociationsAndUserImages() async throws {
        let loc = tmpLoc(); let st = EnrichmentStore(locations: loc); let it = item(), other = item("Other", bundle: "b.other")
        let mine = try await st.setUserImage(key: ProductKey.make(for: it), clean: ImageSanitizer.sanitize(png(300, 200)).get())
        let fetched = try await st.setFetchedCover(key: ProductKey.make(for: other), clean: ImageSanitizer.sanitize(png(200, 300)).get(), sourceURL: URL(string: "https://x.example/i.png")!)
        await st.clearFetchedCovers()
        #expect(await st.coverData(for: mine) != nil)                                      // manual choice still recoverable
        #expect(await st.coverData(for: fetched) == nil)                                   // fetched cover gone, but…
        let rec = await st.record(ProductKey.make(for: other)); #expect(rec?.cover?.sourceURL == "https://x.example/i.png")   // …the source is kept: re-fetchable
    }
    @Test func removeDeletesRecordAndItsImage() async throws {
        let loc = tmpLoc(); let st = EnrichmentStore(locations: loc); let it = item()
        let r = try await st.setUserImage(key: ProductKey.make(for: it), clean: ImageSanitizer.sanitize(png(100, 100)).get())
        await st.remove(key: ProductKey.make(for: it))
        #expect(await st.record(ProductKey.make(for: it)) == nil); #expect(await st.coverData(for: r) == nil)
    }
    @Test func newerSchemaIsRefusedAndCorruptFileIsKeptAside() async throws {
        let loc = tmpLoc(); try loc.createDirectories()
        try Data(#"{"schemaVersion":99,"records":{},"notFound":{}}"#.utf8).write(to: loc.enrichmentFile)
        await #expect(throws: StoreError.self) { try await EnrichmentStore(locations: loc).load() }
        let loc2 = tmpLoc(); try loc2.createDirectories(); try Data("not json".utf8).write(to: loc2.enrichmentFile)
        await #expect(throws: StoreError.self) { try await EnrichmentStore(locations: loc2).load() }
        let kept = try FileManager.default.contentsOfDirectory(atPath: loc2.appSupport.path).filter { $0.contains("corrupt") }
        #expect(kept.count == 1)
    }
    @Test func atomicSaveLeavesValidJSON() async throws {
        let loc = tmpLoc(); let st = EnrichmentStore(locations: loc)
        for i in 0..<20 { await st.upsert(ProductRecord(key: "k\(i)")) }
        let f = try JSONStore<EnrichmentFile>(url: loc.enrichmentFile).load(); #expect(f?.records.count == 20 && f?.schemaVersion == 1)
    }
    @Test func fetchedAndUserCoversLiveInDifferentFolders() {
        let l = tmpLoc(); #expect(l.userCoversDir.path.hasPrefix(l.appSupport.path)); #expect(l.fetchedCoversDir.path.hasPrefix(l.caches.path))
        #expect(l.fetchedCoversDir != l.previewCacheDir)
    }
}

@Suite struct DiscoveryStatesTests {
    private func svc(_ search: SearchProvider, _ replies: [String: StubFetcher.Reply] = [:]) -> EnrichmentService {
        let loc = tmpLoc()
        return EnrichmentService(store: EnrichmentStore(locations: loc), fetcher: StubFetcher(replies), search: search, now: { Date(timeIntervalSince1970: 1_000_000) })
    }
    @Test func searchUnavailableIsNeverCountedAsNotFound() async {
        let s = await svc(NoSearchProvider()).fill([item("A One", bundle: "a.1"), item("B Two", bundle: "b.2")])
        #expect(s.searchUnavailable == 2 && s.notFound == 0 && s.errors == 0 && s.network == 0)
    }
    @Test func emptyResultsAfterRealSearchIsNotFound() async {
        let s = await svc(StubSearch(.success([]))).fill([item()])
        #expect(s.notFound == 1 && s.searchUnavailable == 0)
    }
    @Test func searchNetworkFailureIsNetworkNotNotFound() async {
        let s = await svc(StubSearch(.failure(SearchFailure.offline))).fill([item()])
        #expect(s.network == 1 && s.notFound == 0)
        let r = await svc(StubSearch(.failure(SearchFailure.rateLimited))).fill([item()])
        #expect(r.errors == 1 && r.notFound == 0)
    }
    @Test func braveRequestShapeKeylessAndNoPrivateData() async throws {
        let f = StubFetcher([:])
        let none = BraveSearchProvider(fetcher: f, keyProvider: { nil })
        await #expect(throws: SearchNotConfigured.self) { try await none.search(LookupQuery(item: item())) }
        #expect(f.urls.isEmpty)                                            // no key → nothing is sent
        let json = Data(#"{"web":{"results":[{"title":"Acme Glow – Acme","url":"https://acme.example/glow","description":"x"},{"title":"dup","url":"https://acme.example/glow"},{"title":"bad","url":"http://127.0.0.1/x"},{"title":"ftp","url":"ftp://a.example/x"}]}}"#.utf8)
        let p = BraveSearchProvider(fetcher: StubFetcher([:]), keyProvider: { "KEY123" })
        _ = p
        let fetcher = StubFetcher([:])
        let q = BraveSearchProvider.queryText(LookupQuery(item: item()))
        #expect(!q.contains("/Users/") && !q.contains("jane.doe") && !q.contains("ofx.bundle") && q.contains("Acme Glow"))
        let c = try BraveSearchProvider.parse(json)
        #expect(c.map(\.pageURL.absoluteString) == ["https://acme.example/glow"])
        _ = fetcher
    }
    @Test func braveRequestCarriesKeyHeaderOnlyToTheApiHost() async throws {
        let f = StubFetcher([:])   // every URL answers 404, which maps to a bad response; we inspect what was sent
        let p = BraveSearchProvider(fetcher: f, keyProvider: { "KEY123" })
        _ = try? await p.search(LookupQuery(item: item()))
        #expect(f.urls.count == 1 && f.urls[0].hasPrefix("https://api.search.brave.com/res/v1/web/search?"))
        #expect(f.limits[0].extraHeaders["X-Subscription-Token"] == "KEY123" && f.limits[0].maxRedirects == 0)
        #expect(!f.urls[0].contains("KEY123"))                              // key is a header, never in the URL
    }
    @Test func braveStatusMapping() async {
        for (code, expected) in [(401, SearchFailure.unauthorized), (403, .unauthorized), (429, .rateLimited)] {
            let u = BraveSearchProvider.endpoint
            let f = StubFetcher([:]); _ = u
            let p = BraveSearchProvider(fetcher: StatusFetcher(.http(code)), keyProvider: { "k" })
            do { _ = try await p.search(LookupQuery(item: item())); Issue.record("expected throw") } catch let e as SearchFailure { #expect(e == expected) } catch { Issue.record("wrong error \(error)") }
            _ = f
        }
        let off = BraveSearchProvider(fetcher: StatusFetcher(.timeout), keyProvider: { "k" })
        do { _ = try await off.search(LookupQuery(item: item())); Issue.record("expected throw") } catch let e as SearchFailure { #expect(e == .offline) } catch { Issue.record("wrong error") }
    }
}

private struct StatusFetcher: HTTPFetcher {
    let err: FetchError; init(_ e: FetchError) { err = e }
    func fetch(_ url: URL, limits: FetchLimits) async throws -> FetchResult { throw err }
}
