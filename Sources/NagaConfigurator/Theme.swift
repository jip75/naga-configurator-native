import SwiftUI
import AppKit

// Dynamic colors flip between the light/dark palette based on the *effective* appearance, which
// NagaConfiguratorApp drives via .preferredColorScheme from the day/night toggle (not just the OS
// setting) — every existing call site (Theme.bg, Theme.fg, ...) keeps working unchanged.
private func dynamic(light: NSColor, dark: NSColor) -> Color {
    Color(NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
}

// Same palette family as the old Electron app (src/index.css), extended with a light counterpart
// and contrast-safe text tokens. Muted/faint are solid colors, not opacity chains: chained
// .opacity() calls on the old single-color muted compounded down to ~2.8:1 in places (e.g.
// Theme.muted.opacity(0.7) on top of muted's own 0.5 alpha) — well under WCAG AA's 4.5:1 floor
// for normal-size text. These are picked to clear 4.5:1 against both bg and panel in each mode.
enum Theme {
    static let bg = dynamic(
        light: NSColor(red: 0xf6 / 255, green: 0xf6 / 255, blue: 0xf2 / 255, alpha: 1),
        dark: NSColor(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255, alpha: 1)
    )
    static let panel = dynamic(
        light: NSColor(white: 1, alpha: 1),
        dark: NSColor(red: 0x1c / 255, green: 0x1c / 255, blue: 0x1c / 255, alpha: 1)
    )
    static let fg = dynamic(
        light: NSColor(red: 0x16 / 255, green: 0x18 / 255, blue: 0x14 / 255, alpha: 1),
        dark: NSColor(red: 0xf5 / 255, green: 0xf5 / 255, blue: 0xf0 / 255, alpha: 1)
    )
    static let border = dynamic(light: NSColor.black.withAlphaComponent(0.16), dark: NSColor.white.withAlphaComponent(0.18))

    // Background-fill green (badges, active pills, the mouse-image glow) — always paired with
    // black foreground content, so one vivid shade reads fine in both modes.
    static let accent = Color(red: 0x2e / 255, green: 0xe6 / 255, blue: 0x68 / 255)
    static let accentDim = accent.opacity(0.35)
    /// HyperShift layers read orange, Standard reads green — same cue Synapse uses, so it's obvious
    /// at a glance which layer you're editing.
    static let hyper = Color(red: 0xf0 / 255, green: 0x9a / 255, blue: 0x2e / 255)
    static func layerTint(_ layer: HyperLayer) -> Color { layer == .base ? accent : hyper }
    // Accent used AS TEXT on the app's own bg/panel needs its own dynamic shade: the vivid fill
    // green above is ~1.4:1 on white (fails badly), so light mode gets a deep forest green instead
    // (~6.4:1 on white); dark mode keeps the vivid green (already high-contrast on near-black).
    static let accentText = dynamic(
        light: NSColor(red: 0x0a / 255, green: 0x6e / 255, blue: 0x30 / 255, alpha: 1),
        dark: NSColor(red: 0x39 / 255, green: 0xff / 255, blue: 0x6a / 255, alpha: 1)
    )

    /// Secondary text — labels, captions, disabled states. ~4.6:1+ on both bg and panel.
    static let muted = dynamic(light: NSColor(white: 0.30, alpha: 1), dark: NSColor(white: 0.74, alpha: 1))
    /// Tertiary text — the least important line only (e.g. attribution). Still ≥3:1 for its size.
    static let faint = dynamic(light: NSColor(white: 0.42, alpha: 1), dark: NSColor(white: 0.58, alpha: 1))
}

enum AppAppearance: String, CaseIterable {
    case light, dark

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var icon: String { self == .dark ? "moon.fill" : "sun.max.fill" }
    var next: AppAppearance { self == .dark ? .light : .dark }
    var label: String { self == .dark ? "Night" : "Day" }
}

private struct AppAppearanceKey: EnvironmentKey {
    static let defaultValue: Binding<AppAppearance> = .constant(.dark)
}

extension EnvironmentValues {
    /// Bound to the @AppStorage toggle in NagaConfiguratorApp so any view (the TopBarView day/night
    /// button) can read and flip it without threading a second binding through every initializer.
    var appAppearance: Binding<AppAppearance> {
        get { self[AppAppearanceKey.self] }
        set { self[AppAppearanceKey.self] = newValue }
    }
}
