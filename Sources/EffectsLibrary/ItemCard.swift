// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import EffectsLibraryCore

struct ItemCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.displayScale) private var displayScale
    let item: EffectItem

    private var selected: Bool { state.selectedItemID == item.id }
    private var sourceProblem: Bool { state.source(for: item).map { $0.availability != .available } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.showPreviews { previewArea }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: item.kind.symbol).foregroundStyle(Theme.Palette.accent).accessibilityHidden(true)
                Text(item.name).typo(.headline).lineLimit(2).truncationMode(.tail)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(subtitle).typo(.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
            HStack(spacing: 6) {
                Tag(text: item.kind.title, emphasized: false)
                if item.state == .disabled { Tag(text: "Disabled", emphasized: true) }
                if state.isDuplicate(item) { Tag(text: "Duplicate", emphasized: false) }
                if sourceProblem { Tag(text: "Source unavailable", emphasized: true) }
                if item.vendor == nil || item.version == nil { Tag(text: "Metadata incomplete", emphasized: false) }
            }
            .lineLimit(1)
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius).fill(Theme.Palette.surface))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius)
                .strokeBorder(selected ? Theme.Palette.accent : Theme.Palette.separator,
                              lineWidth: selected ? 2 : Theme.hairline(scale: displayScale))
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.kind.title), \(item.vendor ?? "vendor unknown")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Theme.Palette.background)
            switch state.previews[item.id] {
            case .image(let img, let isRender)?:
                Image(nsImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(alignment: .bottomTrailing) { if isRender { Tag(text: "Reference render", emphasized: false).padding(4) } }
            case .unavailable(let reason)? where state.cover(for: item) != nil:
                let _ = reason
                Image(nsImage: state.cover(for: item)!).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(alignment: .bottomTrailing) { Tag(text: state.coverLabel(for: item) ?? "Cover", emphasized: false).padding(4) }
            case .unavailable(let reason)?:
                VStack(spacing: 4) {
                    Image(systemName: item.kind.symbol).font(.system(size: 22)).foregroundStyle(Theme.Palette.textSecondary)
                    Text(reason).typo(.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2).multilineTextAlignment(.center)
                }.padding(6)
            case .loading?, nil:
                ProgressView().controlSize(.small)
            }
        }
        .frame(height: Theme.Metrics.previewHeight)
        .task(id: item.id) { state.loadPreview(item) }
        .accessibilityHidden(true)
    }

    private var subtitle: String {
        [item.vendor ?? "Unknown vendor", item.version.map { "v\($0)" } ?? "version unknown"].joined(separator: " · ")
    }
}

struct Tag: View {
    let text: String
    let emphasized: Bool
    var body: some View {
        Text(text).typo(.caption)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(emphasized ? Theme.Palette.warning : Theme.Palette.textSecondary)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.Palette.surfaceHover))
    }
}
