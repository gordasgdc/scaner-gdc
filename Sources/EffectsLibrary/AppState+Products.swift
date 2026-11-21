// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import EffectsLibraryCore
import EffectsLibraryEngine

struct ConsentRequest: Identifiable { let id = UUID(); let proceed: @MainActor () -> Void }

/// Product cover and details. Separate from previews: a cover is never a render of the effect.
extension AppState {
    func product(for item: EffectItem) -> ProductRecord? { products[ProductKey.make(for: item)] }
    func cover(for item: EffectItem) -> NSImage? { coverImages[ProductKey.make(for: item)] }
    func coverLabel(for item: EffectItem) -> String? {
        guard let c = product(for: item)?.cover else { return nil }
        return c.origin == .userLocal ? "Your image" : "Product cover (online)"
    }

    func loadProducts() async {
        _ = try? await enrichmentStore.load()
        let all = await enrichmentStore.allRecords()
        var imgs: [String: NSImage] = [:]
        for (k, r) in all { if let d = await enrichmentStore.coverData(for: r), let i = NSImage(data: d) { imgs[k] = i } }
        products = all; coverImages = imgs
    }

    private func apply(_ r: ProductRecord?, key: String) async {
        if let r { products[key] = r; if let d = await enrichmentStore.coverData(for: r), let i = NSImage(data: d) { coverImages[key] = i } else { coverImages[key] = nil } }
        else { products[key] = nil; coverImages[key] = nil }
    }

    /// Items with no representative image of any kind: no preview image available and no cover chosen/found.
    func needsCover(_ item: EffectItem) -> Bool {
        if cover(for: item) != nil { return false }
        if product(for: item)?.status == .rejected { return false }
        if case .image? = previews[item.id] { return false }
        return item.previewSupport == .none || { if case .unavailable? = previews[item.id] { return true } else { return false } }()
    }

    // MARK: online actions require the user's explicit opt-in (first use explains what is sent)

    func withOnlineConsent(_ action: @escaping @MainActor () -> Void) {
        if onlineLookupEnabled { action() } else { pendingConsent = ConsentRequest(proceed: { [weak self] in self?.onlineLookupEnabled = true; action() }) }
    }

    func findCoverAndDetails(_ item: EffectItem) {
        withOnlineConsent { [self] in
            productMessage = nil; enrichProgress = (0, 1)
            enrichTask = Task { [self] in
                let out = await enrichment.lookup(item, explicit: true)
                enrichProgress = nil
                let key = ProductKey.make(for: item)
                await apply(await enrichmentStore.record(key), key: key)
                switch out {
                case .updated: productMessage = "Details saved from the official page."
                case .proposed: productMessage = "Found a possible match. Please confirm or reject it in the Product section."
                case .searchUnavailable:
                    productMessage = "No search was made: automatic search is not set up (Settings → Product details). You can associate the official page yourself."
                    pendingAssociate = item
                case .candidates(let c, let amb):
                    transientCandidates[item.id] = c
                    productMessage = amb ? "Several similar pages were found. Open them below, then associate the right one yourself." : "A possible page was found. Open it below, then associate it yourself."
                case .notFound(let m): productMessage = m + " You can associate the official page yourself."
                case .skipped(let m): productMessage = "Skipped: \(m)."
                case .failed(let m, let off): productMessage = off ? "Could not reach the internet. The app keeps working offline." : m
                case .cancelled: productMessage = "Cancelled."
                }
            }
        }
    }

    func associatePage(_ item: EffectItem, address: String) {
        withOnlineConsent { [self] in
            enrichProgress = (0, 1)
            Task { [self] in
                let out = await enrichment.associateOfficialPage(item, address: address)
                enrichProgress = nil
                let key = ProductKey.make(for: item); await apply(await enrichmentStore.record(key), key: key)
                switch out {
                case .updated: productMessage = "Official page associated; details saved."
                case .proposed: productMessage = "Page associated, but it may not match this item. Please check the details."
                case .notFound(let m): productMessage = "Page associated. \(m)"
                case .failed(let m, let off): productMessage = off ? "Page saved. No internet connection right now." : m
                default: break
                }
            }
        }
    }

    func chooseLocalImage(_ item: EffectItem) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]; panel.allowsMultipleSelection = false
        panel.message = "Choose an image for “\(item.name)”. It is copied into the app's own storage."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { [self] in
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 8 * 1024 * 1024, let data = try? Data(contentsOf: url) else {
                productMessage = "That image is too large or could not be read."; return }
            switch await enrichment.setLocalImage(item, data: data) {
            case .success: let key = ProductKey.make(for: item); await apply(await enrichmentStore.record(key), key: key); productMessage = "Image saved."
            case .failure(let e): productMessage = e.description
            }
        }
    }

    func acceptProposedImage(_ item: EffectItem) {
        withOnlineConsent { [self] in
            Task { [self] in
                let key = ProductKey.make(for: item)
                switch await enrichment.acceptProposedImage(key: key) {
                case .success(let r): await apply(r, key: key); productMessage = "Cover saved locally."
                case .failure(let e): productMessage = e.description
                }
            }
        }
    }

    func confirmProposal(_ item: EffectItem) {
        Task { [self] in
            let key = ProductKey.make(for: item)
            if var r = await enrichmentStore.record(key) { r.status = .confirmed; r.ambiguity = nil; await enrichmentStore.upsert(r); await apply(r, key: key) }
        }
    }
    func rejectProposal(_ item: EffectItem) { Task { [self] in let key = ProductKey.make(for: item); await enrichmentStore.reject(key: key); await apply(await enrichmentStore.record(key), key: key) } }
    func removeProductData(_ item: EffectItem) { Task { [self] in let key = ProductKey.make(for: item); await enrichmentStore.remove(key: key); await apply(nil, key: key); productMessage = "Cover and online data removed." } }

    // MARK: batch (explicit selection, progress, cancel, summary)

    func prepareFill(_ items: [EffectItem]) {
        let todo = items.filter { needsCover($0) }
        if todo.isEmpty { productMessage = "Every selected item already has an image."; return }
        pendingBatch = todo; enrichSummary = nil
    }

    func startFill() {
        guard let items = pendingBatch else { return }
        onlineLookupEnabled = true   // the batch sheet shows the same disclosure as the first-use sheet; pressing Start is the opt-in
        do {
            enrichProgress = (0, items.count); enrichSummary = nil
            enrichTask = Task { [self] in
                let s = await enrichment.fill(items) { d, t in Task { @MainActor in self.enrichProgress = (d, t) } }
                enrichProgress = nil; enrichSummary = s
                for (k, v) in s.candidates { transientCandidates[k] = v }
                await loadProducts()
            }
        }
    }
    func cancelEnrichment() { enrichTask?.cancel() }
    func clearFetchedCovers() { Task { [self] in await enrichmentStore.clearFetchedCovers(); await loadProducts() } }
}
