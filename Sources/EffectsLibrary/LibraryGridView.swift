// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import EffectsLibraryCore

struct LibraryGridView: View {
    @Environment(AppState.self) private var state
    @FocusState private var gridFocused: Bool

    var body: some View {
        let items = state.visibleItems
        if state.sidebar == .activity { ActivityView() } else {
        VStack(spacing: 0) {
        StatusBanner()
        GeometryReader { geo in
            let spacing = Theme.Metrics.cardSpacing
            let inner = max(geo.size.width - spacing * 2, Theme.Metrics.cardMinWidth)
            let columns = max(1, Int((inner + spacing) / (Theme.Metrics.cardMinWidth + spacing)))
            ScrollViewReader { proxy in
                ScrollView {
                    if items.isEmpty {
                        EmptyResultsView().frame(maxWidth: .infinity).padding(.top, 80)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columns),
                                  spacing: spacing) {
                            ForEach(items) { item in
                                ItemCard(item: item)
                                    .id(item.id)
                                    .onTapGesture { state.selectedItemID = item.id; gridFocused = true }
                                    .contextMenu { ItemContextMenu(item: item) }
                            }
                        }
                        .padding(spacing)
                    }
                }
                .focusable()
                .focused($gridFocused)
                .onMoveCommand { dir in
                    switch dir {
                    case .left: state.moveSelection(by: -1)
                    case .right: state.moveSelection(by: 1)
                    case .up: state.moveSelection(by: -columns)
                    case .down: state.moveSelection(by: columns)
                    @unknown default: break
                    }
                }
                .onChange(of: state.selectedItemID) { _, id in
                    if let id { withAnimation(.none) { proxy.scrollTo(id) } }
                }
            }
        }
        }
        .navigationTitle(title)
        .navigationSubtitle("\(items.count) items")
        .accessibilityLabel("Library items")
        }
    }

    private var title: String {
        switch state.sidebar {
        case .all: "All Items"
        case .duplicates: "Duplicates"
        case .disabled: "Disabled"
        case .activity: "Activity"
        case .kind(let k): k.title
        case .source(let id): state.sources.first { $0.id == id }?.displayName ?? "Source"
        }
    }
}

struct EmptyResultsView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(spacing: 6) {
            Text("No items match").typo(.headline).foregroundStyle(Theme.Palette.textPrimary)
            if state.sidebar == .disabled { Text("Nothing is disabled. Items you move to Disabled appear here and can be restored.") }
            else if case .source(let id) = state.sidebar, let src = state.sources.first(where: { $0.id == id }) {
                switch src.availability {
                case .unavailable(let reason): Text("This source could not be read: \(reason)")
                case .notScanned: Text("This source has not been scanned yet.")
                case .missing: Text("This folder does not exist on this Mac.")
                case .available: Text("Try clearing the search or filters.")
                }
            } else {
                Text("Try clearing the search or filters.")
            }
        }
        .typo(.body).foregroundStyle(Theme.Palette.textSecondary)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

struct ItemContextMenu: View {
    @Environment(AppState.self) private var state
    let item: EffectItem
    var body: some View {
        Button("Reveal in Finder") { state.reveal(item) }
        Button("Copy Path") { state.copyPath(item) }
        Divider()
        Button("Regenerate Preview") { state.loadPreview(item, regenerate: true) }
            .disabled(item.previewSupport == .none)
        if item.state == .active { Button("Move to Disabled…") { state.requestDisable(item) } }
        else { Button("Restore…") { state.requestRestore(item) } }
    }
}

/// Origin of the data and the outcome of the last scan, never hidden.
struct StatusBanner: View {
    @Environment(AppState.self) private var state
    var body: some View {
        let msg: String? = state.origin == .mock ? "Sample data (mock). Not your real library."
            : state.origin == .lastKnown && !state.isScanning ? "Showing the last known inventory. Rescan to refresh."
            : state.lastScanNote
        if let msg {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "info.circle").accessibilityHidden(true)
                    Text(msg).typo(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .foregroundStyle(Theme.Palette.warning)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                Hairline()
            }
        }
    }
}

struct ActivityView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        List {
            if !state.recoveryNotes.isEmpty {
                Section("Recovered after an interruption") { ForEach(state.recoveryNotes, id: \.self) { Text($0).typo(.body) } }
            }
            Section("Operations") {
                if state.journalEntries.isEmpty { Text("No operations yet. Moving an item to Disabled is recorded here.").typo(.body).foregroundStyle(Theme.Palette.textSecondary) }
                ForEach(state.journalEntries, id: \.opID) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(e.kind == .disable ? "Disable" : "Restore") · \(e.itemName) · \(e.phase.rawValue)").typo(.headline)
                        Text("\(e.from) → \(e.to)").typo(.mono).foregroundStyle(Theme.Palette.textSecondary).textSelection(.enabled)
                        if !e.message.isEmpty { Text(e.message).typo(.caption).foregroundStyle(Theme.Palette.textSecondary) }
                        Text(e.timestamp.formatted(date: .abbreviated, time: .standard)).typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Activity")
    }
}
