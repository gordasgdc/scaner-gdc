// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore
import EffectsLibraryEngine
import EffectsLibraryTestSupport

// gel-bench: development tool. Synthetic data only; all output under $GEL_OUT (external storage). No pass/fail thresholds.
//   gel-bench fixtures <dir> <storageRoot> [ofx vst3 au vst luts dctls]   build a synthetic library and register it as custom sources
//   gel-bench bench [outfile.json]                                        measure scan / query / preview / memory

func rssMB() -> Double {
    var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
    return r == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
}
func time<T>(_ f: () async throws -> T) async rethrows -> (T, Double) { let t = Date(); let v = try await f(); return (v, Date().timeIntervalSince(t) * 1000) }

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: gel-bench fixtures|bench"); exit(2) }

// REAL network probe (kept out of the deterministic test suite): gel-bench net-probe <https-url>
// Prints what the real fetcher does with the address: policy verdict, status, content type, size, extracted metadata.
if args[1] == "net-probe" {
    // modes: page <url> | image <url> | redirect <url> [maxRedirects] | timeout <url> <seconds> | cancel <url> <delayMs>
    var a = Array(args.dropFirst(2))
    var mode = "page"
    if let f = a.first, ["page", "image", "redirect", "timeout", "cancel"].contains(f) { mode = f; a.removeFirst() }
    guard let first = a.first, let u = URL(string: first) else { print("usage: gel-bench net-probe [page|image|redirect|timeout|cancel] <url> [n]"); exit(2) }
    if case .failure(let r) = URLPolicy.validate(u) { print("policy: BLOCKED (\(r))"); exit(0) }
    print("mode: \(mode)  policy: allowed  host: \(u.host ?? "?")")
    let n = a.count > 1 ? Double(a[1]) : nil
    let f = URLSessionFetcher()
    let t0 = Date()
    func ms() -> String { String(format: "%.0f ms", Date().timeIntervalSince(t0) * 1000) }
    do {
        switch mode {
        case "image":
            let r = try await f.fetch(u, limits: .image)
            print("final: \(r.finalURL.host ?? "?")  type: \(r.contentType ?? "?")  bytes: \(r.data.count)  [\(ms())]")
            switch ImageSanitizer.sanitize(r.data) {
            case .success(let c): print("sanitize: OK, re-encoded PNG \(c.png.count) bytes, \(c.width)x\(c.height)")
            case .failure(let e): print("sanitize: REJECTED (\(e))")
            }
        case "redirect":
            let r = try await f.fetch(u, limits: FetchLimits(maxBytes: 512 * 1024, timeout: 10, maxRedirects: Int(n ?? 3)))
            print("final: \(r.finalURL.absoluteString)  bytes: \(r.data.count)  [\(ms())]")
        case "timeout":
            _ = try await f.fetch(u, limits: FetchLimits(maxBytes: 512 * 1024, timeout: n ?? 2))
            print("unexpected success [\(ms())]")
        case "cancel":
            let task = Task { try await f.fetch(u, limits: .page) }
            try? await Task.sleep(nanoseconds: UInt64((n ?? 300) * 1_000_000)); task.cancel()
            do { _ = try await task.value; print("unexpected success [\(ms())]") } catch { print("cancelled → \(error) [\(ms())]") }
        default:
            let r = try await f.fetch(u, limits: .page)
            print("final: \(r.finalURL.host ?? "?")  type: \(r.contentType ?? "?")  bytes: \(r.data.count)  [\(ms())]")
            let m = PageMetadataExtractor.extract(html: r.data, baseURL: r.finalURL)
            print("title: \(m.title ?? "-")\nsite: \(m.siteName ?? "-")\ndescription: \(m.description ?? "-")\nimage: \(m.imageURL?.host ?? "-")")
        }
    } catch { print("result: \(error)  [\(ms())]") }
    exit(0)
}


// REAL update-flow harness (isolated test, never used by the shipped app): drives the real UpdateService/Verifier/Installer
// against a locally built, signed DMG. The network layer is replaced by a local stub; all verification and installation is real.
//   gel-bench update-run <installedVersion> <targetApp> <dmg> <announcedVersion> <workDir> [wrong-sha|wrong-size|cancel]
if args[1] == "update-run" {
    guard args.count >= 7 else { print("usage: gel-bench update-run <installedVersion> <targetApp> <dmg> <announcedVersion> <workDir> [wrong-sha]"); exit(2) }
    let dmg = URL(fileURLWithPath: args[4]); let target = URL(fileURLWithPath: args[3]); let work = URL(fileURLWithPath: args[6], isDirectory: true)
    let mode = args.count > 7 ? args[7] : ""
    let sha = mode == "wrong-sha" ? String(repeating: "0", count: 64) : (try UpdateVerifier.sha256(of: dmg))
    let size = (try FileManager.default.attributesOfItem(atPath: dmg.path)[.size] as? Int) ?? 0
    let pre = "https://github.com/gordasgdc/scaner-gdc/releases/download/v\(args[5])/"
    let man = "{\"version\":\"\(args[5])\",\"build\":\"1\",\"changes\":\"harness\",\"mandatory\":false,\"download_url\":{\"mac\":\"\(pre)\(dmg.lastPathComponent)\"},\"sha256\":\"\(sha)\",\"size\":\(size),\"min_os\":\"14.0\"}"
    struct Stub: HTTPFetcher, HTTPDownloader {
        let manifest: Data; let dmg: URL
        func fetch(_ url: URL, limits: FetchLimits) async throws -> FetchResult { FetchResult(data: manifest, finalURL: url, contentType: "application/json") }
        func download(_ url: URL, maxBytes: Int64, timeout: TimeInterval, to file: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws {
            try FileManager.default.copyItem(at: dmg, to: file); progress(Int64(1), Int64(1))
        }
    }
    let stub = Stub(manifest: Data(man.utf8), dmg: dmg)
    let svc = UpdateService(fetcher: stub, downloader: stub, installedVersion: args[2])
    try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    switch await svc.check() {
    case .failed(let f): print("check: FAILED — \(f)"); exit(1)
    case .upToDate(let i, let l): print("check: up to date (installed \(i), latest \(l))"); exit(0)
    case .available(let o):
        print("check: update available \(o.version)")
        let r = await svc.install(o, target: target, workDir: work, relaunch: false) { print("  phase: \($0)") }
        switch r { case .success(let v): print("install: OK → \(v)"); exit(0); case .failure(let f): print("install: FAILED — \(f)"); exit(1) }
    }
}

if args[1] == "fixtures" {
    guard args.count >= 4 else { print("usage: gel-bench fixtures <dir> <storageRoot> [counts]"); exit(2) }
    let n = args.dropFirst(4).compactMap { Int($0) }
    let c = n.count == 6 ? SyntheticFixtures.Counts(ofx: n[0], vst3: n[1], au: n[2], vst: n[3], luts: n[4], dctls: n[5]) : SyntheticFixtures.Counts(ofx: 6, vst3: 5, au: 4, vst: 2, luts: 8, dctls: 3)
    let root = URL(fileURLWithPath: args[2], isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let (descs, total) = try SyntheticFixtures.populate(root: root, c)
    let st = StorageLocations.rooted(at: URL(fileURLWithPath: args[3], isDirectory: true)); try st.createDirectories()
    let recs = descs.map { CustomSourceRecord(path: $0.url.path, kinds: $0.kinds, bookmark: nil, displayName: $0.displayName) }
    try JSONStore<SourcesFile>(url: st.sourcesFile).save(SourcesFile(custom: recs))
    print("fixtures: \(total) items in \(descs.count) sources under \(root.path)")
    exit(0)
}

if args[1] == "demo-disable" {
    // Synthetic only: disables one fixture item through the real engine so screenshots can show the Disabled/Activity views.
    guard args.count >= 5 else { print("usage: gel-bench demo-disable <storageRoot> <itemName> <libRoot>"); exit(2) }
    let st = StorageLocations.rooted(at: URL(fileURLWithPath: args[2], isDirectory: true))
    let sources = (try JSONStore<SourcesFile>(url: st.sourcesFile).loadValidated() ?? SourcesFile()).custom
    let descs = InventoryAssembler.descriptors(standard: [], custom: sources, disabledOverride: nil)
    let sum = await LibraryScanner().scanAll(descs)
    let inv = InventoryAssembler.assemble(sum.results, journal: nil)
    guard let item = inv.items.first(where: { $0.name == args[3] }) else { print("item not found"); exit(1) }
    let eng = ManagementEngine(journal: OperationJournal(url: st.journalFile))
    let plan = await eng.planDisable(item, sources: descs)
    let out = try await eng.execute(plan, confirmation: Confirmation(planID: plan.id))
    print(out.message); exit(0)
}

if args[1] == "realscan" {
    // Read-only scan of the standard locations on this Mac. Prints counts only (no names, no paths); full detail stays in memory.
    let (summary, ms) = await time { await LibraryScanner().scanAll(StandardSources.all()) }
    var out: [[String: Any]] = []
    for r in summary.results.sorted(by: { $0.descriptor.displayName < $1.descriptor.displayName }) {
        var kinds: [String: Int] = [:]; for i in r.items { kinds[i.kind.rawValue, default: 0] += 1 }
        let status: String = { switch r.availability { case .available: "available"; case .missing: "missing"; case .notScanned: "notScanned"; case .unavailable(let why): "unavailable: " + why } }()
        out.append(["source": r.descriptor.displayName, "status": status, "items": r.items.count, "kinds": kinds, "warnings": r.warnings.count, "truncated": r.truncated, "ms": Int(r.duration * 1000)])
    }
    let rep: [String: Any] = ["total_items": summary.totalItems, "total_ms": Int(ms), "cancelled": summary.cancelled, "merges": summary.merges.count, "sources": out, "rss_mb": Int(rssMB())]
    let d = try JSONSerialization.data(withJSONObject: rep, options: [.prettyPrinted, .sortedKeys])
    if args.count > 2 { try d.write(to: URL(fileURLWithPath: args[2])) }
    print(String(decoding: d, as: UTF8.self)); exit(0)
}

guard args[1] == "bench" else { print("unknown command"); exit(2) }
var report: [String: Any] = ["generated": ISO8601DateFormatter().string(from: Date()), "note": "synthetic data; no thresholds applied", "rss_start_mb": rssMB()]

// 1. Scan time vs inventory size
var scans: [[String: Any]] = []
for n in [100, 1000, 3000] {
    let root = try SyntheticFixtures.workRoot("bench-scan-\(n)")
    let (descs, total) = try SyntheticFixtures.populate(root: root, .init(ofx: n / 5, vst3: n / 5, au: n / 5, vst: n / 5, luts: n / 10, dctls: n / 10))
    let (summary, ms) = await time { await LibraryScanner().scanAll(descs) }
    scans.append(["requested": total, "found": summary.totalItems, "ms": Int(ms), "ms_per_item": (ms / Double(max(total, 1))).rounded(toPlaces: 3), "rss_mb": Int(rssMB())])
    try? FileManager.default.removeItem(at: root)
}
report["scan"] = scans

// 2. Query on 10k items
var items: [EffectItem] = []
for i in 0..<10_000 { items.append(EffectItem(name: "Effect \(i)", kind: ItemKind.allCases[i % ItemKind.allCases.count], sourceID: "s\(i % 5)", path: "/synthetic/\(i)", vendor: i % 7 == 0 ? nil : "Vendor \(i % 11)", bundleIdentifier: "id.\(i % 8000)")) }
var q = LibraryQuery(); q.searchText = "effect 99"
let (_, qs) = await time { _ = q.apply(to: items) }
var q2 = LibraryQuery(); q2.onlyDuplicates = true; q2.sortKey = .vendor
let (_, qd) = await time { _ = q2.apply(to: items) }
report["query_10k"] = ["search_ms": Int(qs), "duplicates_sort_ms": Int(qd)]

// 3. LUT parse + render by size, and preview cache miss/hit
let work = try SyntheticFixtures.workRoot("bench-preview")
var luts: [[String: Any]] = []
let cache = PreviewCache(directory: work.appendingPathComponent("cache"), maxBytes: 64 << 20)
let svc = PreviewService(cache: cache)
for size in [17, 33, 65] {
    let f = work.appendingPathComponent("L\(size).cube")
    try SyntheticFixtures.cube3D(size: size, title: "bench") { (min($0 * 1.1, 1), $1, $2) }.write(to: f, atomically: true, encoding: .utf8)
    let item = EffectItem(name: "L\(size)", kind: .lut, sourceID: "b", path: f.path, previewSupport: .lutCube)
    let (_, miss) = await time { _ = await svc.preview(for: item) }
    let (_, hit) = await time { _ = await svc.preview(for: item) }
    luts.append(["size": size, "miss_ms": Int(miss), "hit_ms": hit.rounded(toPlaces: 2), "rss_mb": Int(rssMB())])
}
report["preview"] = luts
try? FileManager.default.removeItem(at: work)
report["rss_end_mb"] = Int(rssMB())

let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
if args.count > 2 { try data.write(to: URL(fileURLWithPath: args[2])) }
print(String(decoding: data, as: UTF8.self))

extension Double { func rounded(toPlaces p: Int) -> Double { let m = pow(10, Double(p)); return (self * m).rounded() / m } }
