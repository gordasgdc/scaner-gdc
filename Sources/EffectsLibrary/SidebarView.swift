// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import EffectsLibraryCore

extension ItemKind {
    var symbol: String {
        switch self {
        case .ofx: "wand.and.rays"
        case .lut: "cube"
        case .dctl: "chevron.left.forwardslash.chevron.right"
        case .vst3, .vst: "waveform"
        case .audioUnit: "speaker.wave.2"
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        List(selection: $state.sidebar) {
            Section("Library") {
                row("All Items", "square.grid.2x2", count: state.activeItems.count).tag(SidebarSelection.all)
                row("Duplicates", "square.on.square", count: state.items.filter(state.isDuplicate).count).tag(SidebarSelection.duplicates)
                row("Disabled", "pause.circle", count: state.disabledCount).tag(SidebarSelection.disabled)
                row("Activity", "clock.arrow.circlepath", count: state.journalEntries.count).tag(SidebarSelection.activity)
            }
            Section("Types") {
                ForEach(ItemKind.allCases, id: \.self) { kind in
                    row(kind.title, kind.symbol, count: state.count(for: kind)).tag(SidebarSelection.kind(kind))
                }
            }
            Section("Sources") {
                ForEach(state.sources) { src in
                    sourceRow(src).tag(SidebarSelection.source(src.id))
                        .contextMenu {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: src.path)]) }
                                .disabled(src.availability != .available)
                            if state.isCustom(src.id) { Button("Remove Source") { state.removeCustomSource(src.id) } }
                        }
                }
                Button { state.addCustomSource() } label: { Label("Add Source…", systemImage: "plus") }
                    .buttonStyle(.plain).typo(.body).foregroundStyle(Theme.Palette.accent)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Hairline()
                if state.isScanning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(state.scanProgress.map { "Scanning \($0.sourcesDone)/\($0.sourcesTotal) · \($0.itemsFound) found" } ?? "Scanning…").typo(.caption)
                        Spacer()
                        Button("Cancel") { state.cancelScan() }.controlSize(.small)
                    }
                    .padding(.horizontal, Theme.Metrics.cardPadding).padding(.top, 6)
                }
                Text(state.dataOriginNote)
                    .typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Metrics.cardPadding)
            }
            .background(Theme.Palette.sidebar)
        }
    }

    private func row(_ title: String, _ symbol: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: symbol).typo(.body).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)").typo(.caption).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) items")
    }

    private func sourceRow(_ src: LibrarySource) -> some View {
        let (symbol, status): (String, String) = switch src.availability {
        case .available: ("folder", "available")
        case .unavailable: ("exclamationmark.triangle", "unavailable")
        case .notScanned: ("folder.badge.questionmark", "not scanned")
        case .missing: ("folder", "not found")
        }
        return HStack {
            Label(src.displayName, systemImage: symbol)
                .typo(.body).lineLimit(1)
                .foregroundStyle(src.availability == .available ? Theme.Palette.textPrimary : Theme.Palette.warning)
            Spacer(minLength: 4)
            Text("\(state.count(forSource: src.id))").typo(.caption).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
        }
        .help(src.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(src.displayName), \(status), \(state.count(forSource: src.id)) items")
    }
}
