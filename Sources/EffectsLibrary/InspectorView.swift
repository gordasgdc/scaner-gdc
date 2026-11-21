// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import EffectsLibraryCore

struct InspectorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if let item = state.selectedItem { ItemInspector(item: item) }
            else {
                Text("Select an item to see its details.")
                    .typo(.body).foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Palette.sidebar)
    }
}

private struct ItemInspector: View {
    @Environment(AppState.self) private var state
    let item: EffectItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.name).typo(.title).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                previewSection
                ProductSection(item: item)
                group("Package") {
                    field("Type", item.kind.title)
                    field("Vendor", item.vendor)
                    field("Version", item.version)
                    field("Identifier", item.bundleIdentifier)
                    field("Architectures", item.architectures?.joined(separator: ", "))
                    field("Size", item.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) })
                    field("Modified", item.modified.map { $0.formatted(date: .abbreviated, time: .omitted) })
                }
                group("Location") {
                    field("Source", state.source(for: item)?.displayName)
                    if item.state == .disabled { field("Original", item.originalPath) }
                    if let src = state.source(for: item), src.availability != .available {
                        Text(sourceNote(src)).typo(.caption).foregroundStyle(Theme.Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(item.path).typo(.mono).textSelection(.enabled).foregroundStyle(Theme.Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.exposedEffects.isEmpty {
                    group("Effects exposed to the host") {
                        ForEach(item.exposedEffects, id: \.self) { Text($0).typo(.body) }
                    }
                }
                let others = state.otherLocations(of: item)
                if !others.isEmpty {
                    group("Also found at") {
                        ForEach(others) { o in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.path).typo(.mono).textSelection(.enabled)
                                Text([o.version.map { "v\($0)" }, o.sourceID].compactMap { $0 }.joined(separator: " · "))
                                    .typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                    }
                }
                group("Actions") {
                    VStack(alignment: .leading, spacing: 6) {
                        Button("Copy Path") { state.copyPath(item) }
                        Button("Reveal in Finder") { state.reveal(item) }
                        if item.state == .active { Button("Move to Disabled…") { state.requestDisable(item) } }
                        else { Button("Restore…") { state.requestRestore(item) } }
                        Button("Regenerate Preview") { state.loadPreview(item, regenerate: true) }.disabled(item.previewSupport == .none)
                    }
                    Text("Present on disk does not mean loaded, compatible or licensed in any host.")
                        .typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Metrics.cardPadding + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var previewSection: some View {
        group("Preview") {
            switch state.previews[item.id] {
            case .image(let img, let isRender)?:
                if isRender, let orig = state.originalReference {
                    HStack(spacing: 6) {
                        labeled("Original", orig); labeled("With LUT", img)
                    }
                    Text("Rendered on a synthetic reference image (sRGB assumed); not your footage and not a host-accurate result.")
                        .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 120).accessibilityLabel("Icon of \(item.name)")
                }
            case .unavailable(let r)?: Text(r).typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            default: ProgressView().controlSize(.small)
            }
        }
        .task(id: item.id) { state.loadPreview(item) }
    }
    private func labeled(_ t: String, _ i: NSImage) -> some View {
        VStack(spacing: 2) { Image(nsImage: i).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 3)); Text(t).typo(.caption).foregroundStyle(Theme.Palette.textSecondary) }
            .accessibilityElement(children: .combine).accessibilityLabel(t)
    }

    private func sourceNote(_ src: LibrarySource) -> String {
        switch src.availability {
        case .unavailable(let r): "Source unavailable: \(r). Shown as last known state."
        case .notScanned: "Source not scanned yet."
        case .missing: "Folder not found on this Mac."
        case .available: ""
        }
    }

    @ViewBuilder private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).typo(.caption).foregroundStyle(Theme.Palette.textSecondary).textCase(.uppercase)
            Hairline()
            content()
        }
    }

    private func field(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).typo(.body).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: true, vertical: false).frame(minWidth: 96, alignment: .leading)
            if let value { Text(value).typo(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            else { Text("Unknown").typo(.body).foregroundStyle(Theme.Palette.disabled).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SearchKeyField: View {
    @Environment(AppState.self) private var state
    @State private var key = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Automatic search — advanced, experimental, off by default").typo(.body).bold()
            Text("The app works fully without it: you can associate an official page and choose your own image at any time, whatever your default browser is. Using the Brave browser does not give you access to the Brave Search API — that is a separate service with its own account, terms and possible costs.")
                .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            Text(state.searchKeyPresent ? "A search key is stored in your Keychain. Automatic discovery is on when online lookup is allowed."
                                        : "Not set up: items are not searched automatically. You can still associate an official page yourself.")
                .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                SecureField("Brave Search API key", text: $key).textFieldStyle(.roundedBorder).accessibilityLabel("Search service key")
                Button("Save") { if SearchKeyStore.save(key) { state.searchKeyPresent = true; key = "" } }.disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Remove") { SearchKeyStore.remove(); state.searchKeyPresent = false }.disabled(!state.searchKeyPresent)
            }
            Text("You need your own account and key from Brave (api-dashboard.search.brave.com); its pricing, limits and terms apply to you, and its standard plan does not allow storing search results. So results are shown in memory only and never saved; only an address you associate yourself is saved. When set, the product's technical name and producer are sent to Brave as a search query. The key stays in your Keychain. Not verified against the live service.")
                .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var includePaths = false

    var body: some View {
        @Bindable var state = state
        Form {
            Picker("Appearance", selection: $state.appearance) { ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) } }
            Picker("Text size", selection: $state.textSize) { ForEach(TextSize.allCases) { Text($0.title).tag($0) } }
            Toggle("Show previews", isOn: $state.showPreviews)
            Section("Preview cache") {
                Picker("Size limit", selection: $state.cacheLimitMB) { ForEach([16, 64, 256, 1024], id: \.self) { Text("\($0) MB").tag($0) } }
                Text("Takes effect at next launch.").typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
                HStack {
                    Button("Clear Cache") { state.clearPreviewCache() }
                    Button("Regenerate Visible Previews") { state.regenerateAllVisible() }.disabled(state.regenerating)
                }
            }
            Section("Product details (online)") {
                Toggle("Allow online lookup of covers and details", isOn: $state.onlineLookupEnabled)
                Text("Optional and off by default. Only a product's technical name, producer and identifier — or an address you provide — are sent; never paths, files, licenses or your inventory.")
                    .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                SearchKeyField()
                Button("Clear Fetched Covers") { state.clearFetchedCovers() }
                Text("Clearing removes downloaded covers only. Associations, details and images you chose are kept.").typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
            Section("Updates") {
                Text("Installed version: \(state.appInfo.version) (\(state.appInfo.build))").typo(.body)
                Toggle("Check for updates when the app opens", isOn: $state.checkUpdatesAtLaunch)
                Button("Check for Updates…") { state.checkForUpdatesManually() }
                Text("The check downloads a small public file (update.json) from the project's website. No identifier, inventory or usage data is sent. Nothing is installed until you choose “Update Now”; the new version is verified (same developer, same app identity) before it replaces this app. This is not telemetry.")
                    .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Disabled items location") {
                Text(state.disabledRootOverride ?? "Next to each source folder (same volume, recommended).").typo(.caption)
                HStack {
                    Button("Choose Folder…") {
                        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                        if p.runModal() == .OK { state.setDisabledRoot(p.url) }
                    }
                    Button("Use Default") { state.setDisabledRoot(nil) }.disabled(state.disabledRootOverride == nil)
                }
                Text("A folder on another volume works too: items are copied and verified before the original is removed.").typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
            Section("Diagnostics") {
                Toggle("Include file paths in export", isOn: $includePaths)
                Toggle("Verbose logging for 10 minutes", isOn: Binding(get: { state.debugLogging }, set: { state.setDebug($0) }))
                HStack {
                    Button("Export Diagnostics…") { state.exportDiagnostics(includePaths: includePaths) }
                    Button("Show Log in Finder") { state.openLogs() }
                    Button("Copy Session ID") { state.copySessionID() }
                }
            }
            Section("Data") { Text(state.dataOriginNote).typo(.caption).foregroundStyle(Theme.Palette.textSecondary) }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 780)
    }
}
