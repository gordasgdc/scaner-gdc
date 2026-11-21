// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore

public struct ScanProgress: Sendable, Equatable {
    public var sourcesTotal: Int
    public var sourcesDone: Int
    public var itemsFound: Int
    public var currentSources: [String]
}

public struct SourceScanResult: Sendable {
    public var descriptor: SourceDescriptor
    public var availability: SourceAvailability
    public var items: [EffectItem]
    public var warnings: [String]
    public var duration: TimeInterval
    public var truncated: Bool
}

public struct ScanSummary: Sendable {
    public var correlationID: String
    public var results: [SourceScanResult]
    public var merges: [RootDeduplicator.Merge]
    public var cancelled: Bool
    public var duration: TimeInterval
    public var totalItems: Int { results.reduce(0) { $0 + $1.items.count } }
}

public enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case sourceFinished(SourceScanResult)
    case finished(ScanSummary)
}

/// Read-only scanner. Reads directory listings and metadata files; never opens plugin binaries beyond the first
/// bytes of the Mach-O header and never executes anything. Cancellation is cooperative (checked per entry).
public struct LibraryScanner: Sendable {
    public var limits: ScanLimits
    public var log: DiagnosticLog?

    public init(limits: ScanLimits = ScanLimits(), log: DiagnosticLog? = nil) { self.limits = limits; self.log = log }

    /// Streams progress and per-source results, ends with `.finished`. Cancelling the consuming task cancels the scan.
    public func scan(_ sources: [SourceDescriptor]) -> AsyncStream<ScanEvent> {
        AsyncStream { cont in
            let task = Task {
                let correlation = Correlation.newID("scan")
                await Correlation.$id.withValue(correlation) {
                    let summary = await self.run(sources, emit: { cont.yield($0) })
                    cont.yield(.finished(summary))
                    cont.finish()
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    /// Convenience for callers that only need the final summary.
    public func scanAll(_ sources: [SourceDescriptor]) async -> ScanSummary {
        var summary: ScanSummary?
        for await ev in scan(sources) { if case .finished(let s) = ev { summary = s } }
        return summary ?? ScanSummary(correlationID: "-", results: [], merges: [], cancelled: true, duration: 0)
    }

    private func run(_ input: [SourceDescriptor], emit: @Sendable (ScanEvent) -> Void) async -> ScanSummary {
        let started = Date()
        let (sources, merges) = RootDeduplicator.reduce(input)
        log?.info("scan", "scan.start", "sources=\(sources.count) merged=\(merges.count)",
                  fields: ["sources": String(sources.count), "merged": String(merges.count)])
        for m in merges { log?.debug("scan", "scan.root.merged", "\(m.dropped) → \(m.into): \(m.reason)") }

        var results: [SourceScanResult] = []
        var progress = ScanProgress(sourcesTotal: sources.count, sourcesDone: 0, itemsFound: 0, currentSources: [])
        emit(.progress(progress))
        await withTaskGroup(of: SourceScanResult.self) { group in
            var next = 0
            func launch() {
                guard next < sources.count else { return }
                let s = sources[next]; next += 1
                progress.currentSources.append(s.displayName)
                group.addTask { await self.scanSource(s) }
            }
            for _ in 0..<min(limits.maxConcurrentSources, sources.count) { launch() }
            while let r = await group.next() {
                results.append(r)
                progress.sourcesDone += 1; progress.itemsFound += r.items.count
                progress.currentSources.removeAll { $0 == r.descriptor.displayName }
                emit(.sourceFinished(r)); emit(.progress(progress))
                if !Task.isCancelled { launch() }
            }
        }
        let cancelled = Task.isCancelled
        let order = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($1.id, $0) })
        results.sort { (order[$0.descriptor.id] ?? 0) < (order[$1.descriptor.id] ?? 0) }
        let summary = ScanSummary(correlationID: Correlation.id ?? "-", results: results, merges: merges, cancelled: cancelled,
                                  duration: Date().timeIntervalSince(started))
        log?.info("scan", cancelled ? "scan.cancelled" : "scan.done", "items=\(summary.totalItems)",
                  fields: ["items": String(summary.totalItems), "ms": String(Int(summary.duration * 1000))])
        return summary
    }

    /// Scans one root. A root that cannot be read is reported as unavailable/missing, never as an empty success.
    public func scanSource(_ s: SourceDescriptor) async -> SourceScanResult {
        let t0 = Date()
        let fm = FileManager.default
        func result(_ a: SourceAvailability, _ items: [EffectItem] = [], _ w: [String] = [], trunc: Bool = false) -> SourceScanResult {
            SourceScanResult(descriptor: s, availability: a, items: items, warnings: w, duration: Date().timeIntervalSince(t0), truncated: trunc)
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: s.url.path, isDirectory: &isDir) else {
            let missing: SourceAvailability = (s.origin == .custom || s.origin == .disabledStore)
                ? .unavailable(reason: "Folder not found (moved, renamed, or its volume is disconnected)") : .missing
            log?.info("scan", "scan.source.missing", s.id)
            return result(missing)
        }
        guard isDir.boolValue else { return result(.unavailable(reason: "Not a folder")) }
        // A permission problem shows up as an error from the very first listing.
        do { _ = try fm.contentsOfDirectory(atPath: s.url.path) }
        catch {
            let why = Self.describe(error)
            log?.warning("scan", "scan.source.unreadable", "\(s.id): \(why)")
            return result(.unavailable(reason: why))
        }

        let reader = PackageReader(limits: limits)
        var items: [EffectItem] = [], warnings: [String] = [], truncated = false
        var seen = Set<String>()
        let wantBundles = s.kinds.contains { $0 != .lut && $0 != .dctl }
        let wantLUT = s.kinds.contains(.lut), wantDCTL = s.kinds.contains(.dctl)
        let errCollector = ErrorBox()
        guard let en = fm.enumerator(at: s.url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                     options: [.skipsHiddenFiles], errorHandler: { url, err in errCollector.add("\(url.lastPathComponent): \(Self.describe(err))"); return true }) else {
            return result(.unavailable(reason: "Cannot enumerate folder"))
        }
        let baseDepth = s.url.pathComponents.count
        while let obj = en.nextObject() {
            guard let url = obj as? URL else { continue }
            if Task.isCancelled { break }
            let depth = url.pathComponents.count - baseDepth
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDirectory = v?.isDirectory == true
            if isDirectory {
                if wantBundles, let k = PackageReader.kind(forBundleName: url.lastPathComponent), s.kinds.contains(k) {
                    en.skipDescendants()               // a bundle is one item; its internals are never indexed
                    items.append(reader.readBundle(url, kind: k, source: s))
                } else if depth >= limits.maxDepthFiles { en.skipDescendants() }
                else if !wantLUT && !wantDCTL && depth >= limits.maxDepthBundles { en.skipDescendants() }
                else if PackageReader.kind(forBundleName: url.lastPathComponent) != nil { en.skipDescendants() }   // other kind's bundle: not ours
            } else if wantLUT || wantDCTL {
                let ext = url.pathExtension.lowercased()
                if wantDCTL, ext == "dctl" { items.append(reader.readFile(url, kind: .dctl, source: s)) }
                else if wantLUT, PackageReader.lutExtensions.contains(ext) { items.append(reader.readFile(url, kind: .lut, source: s)) }
            }
            if items.count >= limits.maxItemsPerSource { truncated = true; break }
        }
        // Defensive de-duplication by canonical path + kind.
        items = items.filter { seen.insert("\($0.kind.rawValue)|\(URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path)").inserted }
        warnings = errCollector.all
        if truncated { warnings.append("Stopped after \(limits.maxItemsPerSource) items (limit)") }
        log?.info("scan", "scan.source.done", "\(s.id) items=\(items.count)", fields: ["source": s.id, "items": String(items.count), "warnings": String(warnings.count)])
        return result(.available, items, Array(warnings.prefix(20)), trunc: truncated)
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError { return "Permission denied" }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EACCES) || ns.code == Int(EPERM) { return "Permission denied" }
        if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain, u.code == Int(EACCES) || u.code == Int(EPERM) { return "Permission denied" }
        return ns.localizedDescription
    }
}

private final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock(); private var list: [String] = []
    func add(_ s: String) { lock.withLock { if list.count < 100 { list.append(s) } } }
    var all: [String] { lock.withLock { list } }
}
