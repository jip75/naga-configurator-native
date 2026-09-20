import SwiftUI

/// rawCode -> display name, ordered for the defaults list. Mirrors ContentView.topButtonLabel's
/// naming for the two top buttons; numbered buttons come from Device.buttons (the same source of
/// truth the mouse diagram uses) so this list can never drift out of sync with what's on-screen.
private let TOP_BUTTON_ORDER: [(rawCode: String, label: String)] = [
    ("topA", "Front Top Button"),
    ("topB", "Rear Top Button"),
]

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                whySection
                defaultsSection
            }
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("About Naga Configurator")
                .font(.system(size: 20, weight: .bold))
            Text("Version \(appVersion) — MkrLab.io, a Jorivan LLC company")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
        }
    }

    private var whySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why this exists")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.accentText)
            Text("""
            I use this mouse one-handed after an injury, so left-click, right-click, and the \
            physical DPI button stay exactly where they are — everything else is fair game. \
            Razer's own Synapse software doesn't run natively on Apple Silicon the way I needed \
            it to, so I built this configurator from scratch: a native macOS app that reads the \
            mouse's raw button signals directly and maps them to whatever I need, per app, per \
            layer.
            """)
            .font(.system(size: 13))
            .foregroundColor(Theme.fg)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
        .cornerRadius(14)
    }

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My defaults")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.accentText)
            Text("These are the button mappings I personally use day to day. They're just a starting point — customize every one of them from the Customize tab.")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(defaultRows, id: \.rawCode) { row in
                    HStack {
                        Text(row.label)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(row.actionLabel)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)

                    if row.rawCode != defaultRows.last?.rawCode {
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                }
            }
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
            .cornerRadius(14)
        }
    }

    private var defaultRows: [(rawCode: String, label: String, actionLabel: String)] {
        let numbered = Device.buttons.map { pos in
            (rawCode: pos.rawCode, label: "Button \(pos.number)", actionLabel: DefaultMapping.value[pos.rawCode]?.base.displayLabel ?? "Unassigned")
        }
        let top = TOP_BUTTON_ORDER.map { entry in
            (rawCode: entry.rawCode, label: entry.label, actionLabel: DefaultMapping.value[entry.rawCode]?.base.displayLabel ?? "Unassigned")
        }
        return numbered + top
    }
}
