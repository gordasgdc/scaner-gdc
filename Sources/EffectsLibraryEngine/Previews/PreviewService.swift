// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore

public enum PreviewSource: String, Sendable { case cache, rendered, bundleIcon }

public enum PreviewResult: Sendable {
    case image(png: Data, source: PreviewSource, isRender: Bool)
    /// No preview, with the reason shown to the user. Never replaced by a generic or fake image.
    case unavailable(reason: String)
}

public struct PreviewBatchSummary: Sendable {
    public var requested = 0, produced = 0, unavailable = 0, cancelled = false
}

/// Produces previews off the main thread: bundle icons (data files only), `.cube` LUT renders on the synthetic reference.
/// DCTL and unsupported formats are `.unavailable` — the code is never compiled or executed.
public actor PreviewService {
    public struct Settings: Sendable, Equatable { public var width = 384, height = 240
        public var maxIconPixel = 128
        public init() {}
        var descriptor: String { "\(width)x\(height)/icon\(maxIconPixel)" } }

    private let cache: PreviewCache
    private let log: DiagnosticLog?
    private let settings: Settings
    private let reference: ReferenceImage
    private let referenceHash: String
    private let reader = PackageReader(limits: ScanLimits())

    public init(cache: PreviewCache, settings: Settings = Settings(), log: DiagnosticLog? = nil) {
        self.cache = cache; self.settings = settings; self.log = log
        reference = ReferenceImage.make(width: settings.width, height: settings.height)
        referenceHash = reference.contentHash
    }

    public func preview(for item: EffectItem, regenerate: Bool = false) async -> PreviewResult {
        switch item.previewSupport {
        case .none: return .unavailable(reason: item.previewNote ?? "No preview available")
        case .bundleIcon: return icon(item, regenerate: regenerate)
        case .lutCube: return lut(item, regenerate: regenerate)
        }
    }

    public func clearCache() { cache.removeAll() }

    /// The untouched reference image (for before/after display).
    public func originalPNG() -> Data? { LUTPreviewRenderer.renderOriginal(reference).flatMap(LUTPreviewRenderer.png) }

    /// Regenerates previews for many items with bounded concurrency; cancellable; reports progress.
    public func regenerate(_ items: [EffectItem], concurrency: Int = 3, progress: @Sendable @escaping (Int, Int) -> Void = { _, _ in }) async -> PreviewBatchSummary {
        var s = PreviewBatchSummary(); s.requested = items.count
        let correlation = Correlation.newID("preview")
        log?.info("preview", "preview.batch.start", "n=\(items.count)", fields: ["items": String(items.count)])
        var done = 0
        await withTaskGroup(of: Bool?.self) { g in
            var next = 0
            func launch() { guard next < items.count else { return }; let it = items[next]; next += 1
                g.addTask { await Correlation.$id.withValue(correlation) {
                    if Task.isCancelled { return nil }
                    if case .image = await self.preview(for: it, regenerate: true) { return true }; return false } } }
            for _ in 0..<min(concurrency, items.count) { launch() }
            while let r = await g.next() {
                done += 1; progress(done, items.count)
                if let r { if r { s.produced += 1 } else { s.unavailable += 1 } } else { s.cancelled = true }
                if Task.isCancelled { s.cancelled = true } else { launch() }
            }
        }
        log?.info("preview", s.cancelled ? "preview.batch.cancelled" : "preview.batch.done", "produced=\(s.produced) unavailable=\(s.unavailable)")
        return s
    }

    // MARK: kinds

    private func icon(_ item: EffectItem, regenerate: Bool) -> PreviewResult {
        let bundle = URL(fileURLWithPath: item.path)
        let plist = reader.readPlist(bundle.appendingPathComponent("Contents/Info.plist"))
        guard let icns = reader.iconURL(bundle: bundle, plist: plist), let h = ContentHasher.sha256(of: icns) else {
            return .unavailable(reason: "No icon resource found in the bundle.")
        }
        let key = PreviewKey(contentHash: h, rendererVersion: 0, settings: "icon\(settings.maxIconPixel)", referenceID: "icon", referenceHash: "-")
        if !regenerate, let d = cache.get(key) { return .image(png: d, source: .cache, isRender: false) }
        guard let png = BundleIconLoader.iconPNG(at: icns, maxPixel: settings.maxIconPixel) else {
            log?.warning("preview", "preview.icon.failed", item.id); return .unavailable(reason: "The icon resource could not be decoded.")
        }
        cache.put(key, png)
        return .image(png: png, source: .bundleIcon, isRender: false)
    }

    private func lut(_ item: EffectItem, regenerate: Bool) -> PreviewResult {
        let url = URL(fileURLWithPath: item.path)
        guard let h = ContentHasher.sha256(of: url) else { return .unavailable(reason: "The LUT file could not be read.") }
        let key = PreviewKey(contentHash: h, settings: settings.descriptor, referenceID: reference.id, referenceHash: referenceHash)
        if !regenerate, let d = cache.get(key) { return .image(png: d, source: .cache, isRender: true) }
        do {
            let lut = try CubeLUT.parse(url: url)
            guard let img = LUTPreviewRenderer.render(lut, reference: reference), let png = LUTPreviewRenderer.png(img) else {
                return .unavailable(reason: "Rendering failed.")
            }
            cache.put(key, png)
            return .image(png: png, source: .rendered, isRender: true)
        } catch let e as CubeLUT.ParseError {
            log?.info("preview", "preview.lut.rejected", "\(item.id): \(e)")
            return .unavailable(reason: "LUT not supported or invalid: \(e)")
        } catch { return .unavailable(reason: "The LUT file could not be read: \(error.localizedDescription)") }
    }
}
