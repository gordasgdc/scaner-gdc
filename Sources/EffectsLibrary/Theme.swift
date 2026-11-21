// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import AppKit

/// Semantic colors and dimensions, defined once (Rule 37). No literal colors in views.
enum Theme {
    private static func dyn(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }

    enum Palette {
        static let background = dyn(dark: 0x14161A, light: 0xF3F4F6)
        static let sidebar = dyn(dark: 0x1A1D22, light: 0xE9EBEE)
        static let surface = dyn(dark: 0x1E2127, light: 0xFFFFFF)
        static let surfaceHover = dyn(dark: 0x262A31, light: 0xF0F1F4)
        static let separator = dyn(dark: 0x2E333B, light: 0xD3D6DB)
        static let textPrimary = dyn(dark: 0xEDEFF2, light: 0x1A1C20)
        static let textSecondary = dyn(dark: 0x9BA1AB, light: 0x5B616B)
        static let accent = dyn(dark: 0xC9894A, light: 0x9A5F26)        // single discreet accent (warm copper)
        static let warning = dyn(dark: 0xD6A545, light: 0x8A6100)
        static let disabled = dyn(dark: 0x6B717B, light: 0x8E8E93)
    }

    enum Metrics {
        static let cardMinWidth: CGFloat = 210
        static let cardSpacing: CGFloat = 12
        static let cardRadius: CGFloat = 8
        static let cardPadding: CGFloat = 12
        static let previewHeight: CGFloat = 84
        static let sidebarMin: CGFloat = 200
        static let inspectorMin: CGFloat = 260
        static let inspectorIdeal: CGFloat = 300
        static let windowMinWidth: CGFloat = 960
        static let windowMinHeight: CGFloat = 600
    }

    /// 1 physical pixel, whatever the screen scale.
    static func hairline(scale: CGFloat) -> CGFloat { 1 / max(scale, 1) }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var title: String { switch self { case .system: "System"; case .dark: "Dark"; case .light: "Light" } }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .dark: .dark; case .light: .light } }
}

enum TextSize: String, CaseIterable, Identifiable {
    case small, normal, large, extraLarge
    var id: String { rawValue }
    var title: String { switch self { case .small: "Small"; case .normal: "Normal"; case .large: "Large"; case .extraLarge: "Extra large" } }
    var scale: CGFloat { switch self { case .small: 0.9; case .normal: 1.0; case .large: 1.15; case .extraLarge: 1.3 } }
}

private struct TextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

enum Typo {
    case title, headline, body, caption, mono
    var base: CGFloat { switch self { case .title: 17; case .headline: 13; case .body: 13; case .caption: 11; case .mono: 11 } }
    var weight: Font.Weight { switch self { case .title: .semibold; case .headline: .semibold; default: .regular } }
}

private struct TypoModifier: ViewModifier {
    let style: Typo
    @Environment(\.textScale) private var scale
    func body(content: Content) -> some View {
        content.font(.system(size: style.base * scale, weight: style.weight, design: style == .mono ? .monospaced : .default))
    }
}

extension View {
    func typo(_ style: Typo) -> some View { modifier(TypoModifier(style: style)) }
}

/// Fine separator adapted to the screen scale.
struct Hairline: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal
    @Environment(\.displayScale) private var scale
    var body: some View {
        let t = Theme.hairline(scale: scale)
        Rectangle().fill(Theme.Palette.separator)
            .frame(width: axis == .vertical ? t : nil, height: axis == .horizontal ? t : nil)
            .accessibilityHidden(true)
    }
}
