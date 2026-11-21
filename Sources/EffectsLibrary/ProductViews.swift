// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import EffectsLibraryCore
import EffectsLibraryEngine

/// What is (and is not) sent, shown before the first online action and in the batch sheet.
struct OnlineDisclosure: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What is sent").typo(.body).bold()
            Text("Only what is needed to identify a product: its technical name, the producer and the identifier read from the package — and, for pages you associate, that address. The page is requested over https like a browser would, with a generic client name.")
                .typo(.caption).fixedSize(horizontal: false, vertical: true)
            if state.searchKeyPresent {
                Text("Because you stored a search key, the technical name and producer are also sent to Brave Search as a query to find the producer's page.")
                    .typo(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Text("Never sent").typo(.body).bold()
            Text("File paths, file contents, LUT/DCTL files, license or serial data, your user name, or your whole inventory. Nothing is uploaded. Images from the internet are used only on this Mac and are never added to the app, its source or its website.")
                .typo(.caption).fixedSize(horizontal: false, vertical: true)
            Text("Everything else works offline. You can turn this off in Settings.").typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

struct ConsentSheet: View {
    @Environment(AppState.self) private var state
    let request: ConsentRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Look up product details online?").typo(.title)
            OnlineDisclosure()
            HStack { Spacer()
                Button("Not now", role: .cancel) { state.pendingConsent = nil }.keyboardShortcut(.cancelAction)
                Button("Allow and continue") { let r = request; state.pendingConsent = nil; r.proceed() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 520)
    }
}

struct AssociateSheet: View {
    @Environment(AppState.self) private var state
    let item: EffectItem
    @State private var address = ""
    var body: some View {
        let parsed = address.isEmpty ? nil : URLPolicy.parse(address)
        VStack(alignment: .leading, spacing: 12) {
            Text("Associate the official page of “\(item.name)”").typo(.title).fixedSize(horizontal: false, vertical: true)
            Text("Paste the producer's page for this product (https://…). The app reads its title, a short description and its link-preview image, and keeps the address as the source.")
                .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            TextField("https://…", text: $address).textFieldStyle(.roundedBorder).accessibilityLabel("Official page address")
            if case .failure(let r)? = parsed { Text(r.description).typo(.caption).foregroundStyle(Theme.Palette.warning) }
            HStack { Spacer()
                Button("Cancel", role: .cancel) { state.pendingAssociate = nil }.keyboardShortcut(.cancelAction)
                Button("Associate") { state.pendingAssociate = nil; state.associatePage(item, address: address) }
                    .keyboardShortcut(.defaultAction).disabled({ if case .success? = parsed { return false } else { return true } }())
            }
        }.padding(20).frame(width: 520)
    }
}

struct BatchSheet: View {
    @Environment(AppState.self) private var state
    let items: [EffectItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fill items without a cover").typo(.title)
            if let s = state.enrichSummary { summary(s) }
            else if let p = state.enrichProgress {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1))) { Text("Looking up \(p.done) of \(p.total)…").typo(.body) }
                HStack { Spacer(); Button("Cancel") { state.cancelEnrichment() } }
            } else {
                Text("\(items.count) selected item\(items.count == 1 ? "" : "s") without an image. Only items whose official page you already associated can be completed in this version; the others are reported as not found.")
                    .typo(.body).fixedSize(horizontal: false, vertical: true)
                OnlineDisclosure()
                HStack { Spacer()
                    Button("Cancel", role: .cancel) { state.pendingBatch = nil }.keyboardShortcut(.cancelAction)
                    Button("Start") { state.startFill() }.keyboardShortcut(.defaultAction)
                }
            }
        }.padding(20).frame(width: 540)
    }
    @ViewBuilder private func summary(_ s: EnrichmentBatchSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.cancelled ? "Cancelled — partial result" : "Done").typo(.body).bold()
            Text("Completed: \(s.completed)").typo(.body)
            if s.manuallyAssociated > 0 { Text("Updated from pages you associated: \(s.manuallyAssociated)").typo(.body) }
            if s.proposed > 0 { Text("Proposed, waiting for your confirmation: \(s.proposed)").typo(.body) }
            if s.candidatesFound > 0 { Text("Pages found by search (shown in each item, not saved): \(s.candidatesFound)").typo(.body) }
            if s.ambiguous > 0 { Text("Ambiguous (several similar pages): \(s.ambiguous)").typo(.body) }
            Text("Not found after searching: \(s.notFound)").typo(.body)
            if s.searchUnavailable > 0 { Text("Not searched — automatic search not set up: \(s.searchUnavailable)").typo(.body) }
            if s.skipped > 0 { Text("Skipped (your choices or earlier rejections): \(s.skipped)").typo(.body) }
            if s.network > 0 { Text("Network problems (no connection or timeout): \(s.network)").typo(.body) }
            if s.errors > 0 { Text("Errors: \(s.errors)").typo(.body) }
            if s.searchUnavailable > 0 {
                Text("Automatic discovery needs a search service key of your own (Settings → Product details). Until then, associate a page from the item's Product section. These items were not searched, so they are not counted as not found.")
                    .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        HStack { Spacer(); Button("Close") { state.pendingBatch = nil; state.enrichSummary = nil }.keyboardShortcut(.defaultAction) }
    }
}

/// Inspector section. The real preview and the package icon stay in "Preview"; this shows the product cover and details,
/// each labelled by origin.
struct ProductSection: View {
    @Environment(AppState.self) private var state
    let item: EffectItem

    var body: some View {
        let rec = state.product(for: item)
        VStack(alignment: .leading, spacing: 6) {
            Text("Product").typo(.caption).foregroundStyle(Theme.Palette.textSecondary).textCase(.uppercase)
            Hairline()
            if let img = state.cover(for: item) {
                Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 160).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 3)).accessibilityLabel("\(state.coverLabel(for: item) ?? "Cover") of \(item.name)")
                Text(state.coverLabel(for: item) ?? "").typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
                if let c = rec?.cover, c.origin == .officialPage {
                    Text("From \(host(c.sourceURL)) · \(c.obtainedAt.formatted(date: .abbreviated, time: .omitted)) · rights not verified: used on this Mac only.")
                        .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let r = rec, r.status != .rejected {
                if r.status == .proposed {
                    Label(r.ambiguity ?? "Found automatically — please confirm.", systemImage: "questionmark.circle").typo(.caption).foregroundStyle(Theme.Palette.warning).fixedSize(horizontal: false, vertical: true)
                    HStack { Button("Confirm") { state.confirmProposal(item) }; Button("Reject") { state.rejectProposal(item) } }
                }
                if let n = r.productName { Text(n).typo(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                if let p = r.producer { Text("Producer: \(p)").typo(.caption).foregroundStyle(Theme.Palette.textSecondary) }
                if let s = r.summary { Text(s).typo(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                if let u = r.officialURL.flatMap(URL.init(string:)) { Link("Official page (\(u.host ?? ""))", destination: u).typo(.caption) }
                if let src = r.sourceURL, let d = r.retrievedAt {
                    Text("Source: \(host(src)) · \(d.formatted(date: .abbreviated, time: .omitted)). Online details never replace the installed version.")
                        .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if r.proposedImageURL != nil, !r.userChoseImage {
                    Button("Use the page image as cover…") { state.acceptProposedImage(item) }
                    Text("The producer's page offers an image; it is downloaded only if you accept, and kept on this Mac.").typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            } else if state.cover(for: item) == nil {
                Text("No cover or details yet. Online lookup is optional and off until you use it.").typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if ProductMatcher.isSuite(item) {
                Text("This package exposes several effects; a cover found for it describes the package, not each effect.").typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if let c = state.transientCandidates[item.id], !c.isEmpty {
                Text("Pages found by the search (kept in memory only, not saved)").typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
                ForEach(c, id: \.pageURL) { cand in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cand.name).typo(.body).fixedSize(horizontal: false, vertical: true)
                        Link(cand.pageURL.host ?? "open", destination: cand.pageURL).typo(.caption)
                    }
                }
                Text("To keep one, open it, copy its address and use “Associate Official Page…”. Only the address you paste is saved.")
                    .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if let m = state.productMessage { Text(m).typo(.caption).foregroundStyle(Theme.Palette.accent).fixedSize(horizontal: false, vertical: true) }
            if state.enrichProgress != nil { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 6) {
                Button("Search Cover and Details") { state.findCoverAndDetails(item) }.disabled(state.enrichProgress != nil)
                Button("Associate Official Page…") { state.pendingAssociate = item }
                Button("Choose Local Image…") { state.chooseLocalImage(item) }
                if rec != nil { Button("Remove Cover and Online Data") { state.removeProductData(item) } }
            }
        }
    }
    private func host(_ s: String?) -> String { s.flatMap { URL(string: $0)?.host } ?? "the source" }
}
