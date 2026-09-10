import SwiftUI

private let NAV_TAB_ICONS: [String: String] = [
    "Customize": "cursorarrow.click",
    "Performance": "gauge.with.dots.needle.67percent",
    "Scrolling": "arrow.up.arrow.down",
    "Lighting": "lightbulb",
]

private func compactLayerLabel(_ layer: HyperLayer) -> String {
    switch layer {
    case .base: return "Std"
    case .hyperA: return "HS A"
    case .hyperB: return "HS B"
    }
}

struct TopBarView: View {
    @EnvironmentObject var hid: NagaHIDManager
    @Environment(\.appAppearance) private var appearance
    // The true width offered by the window, measured once at ContentView's root via
    // GeometryReader and threaded down as a plain value. We deliberately do NOT self-measure
    // with a GeometryReader in our own .background() here: this bar's content is built from
    // .fixedSize() pills/buttons that refuse to compress, so a self-measuring GeometryReader
    // would report the content's own inflated ideal width instead of the narrower width the
    // window actually offered — a circular measurement that meant the compact/stacked tiers
    // never triggered and the bar just clipped instead of collapsing.
    let containerWidth: CGFloat
    let saveState: SaveState
    let onSave: () -> Void
    @Binding var editLayer: HyperLayer
    @Binding var activeTab: String

    // Below `compactWidth`: shrink text/icons but keep one row. Below `stackedWidth`: give up on
    // one row entirely and wrap onto two — the only way to guarantee nothing clips or wraps
    // mid-word all the way down to the ~620pt window minWidth.
    private let compactWidth: CGFloat = 1060
    private let stackedWidth: CGFloat = 760

    private var isCompact: Bool { containerWidth < compactWidth }
    private var isStacked: Bool { containerWidth < stackedWidth }

    var body: some View {
        Group {
            if isStacked {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        brandBlock
                        Spacer(minLength: 8)
                        appearanceToggle
                        saveButton
                    }
                    HStack(spacing: 10) {
                        layerPills
                        Spacer(minLength: 8)
                        navTabs
                    }
                }
            } else {
                HStack(spacing: isCompact ? 10 : 16) {
                    brandBlock
                    Spacer(minLength: 8)
                    layerPills
                    Spacer(minLength: 8)
                    navTabs
                    appearanceToggle
                    saveButton
                }
            }
        }
        .padding(.horizontal, isCompact ? 14 : 24)
        .padding(.vertical, isStacked ? 10 : 12)
        .frame(maxWidth: .infinity)
        .background(Theme.panel.opacity(0.4))
        .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
    }

    // MARK: - Day/night toggle

    private var appearanceToggle: some View {
        Button {
            appearance.wrappedValue = appearance.wrappedValue.next
        } label: {
            Image(systemName: appearance.wrappedValue.icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundColor(Theme.muted)
        .background(Theme.bg)
        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        .clipShape(Circle())
        .help("Switch to \(appearance.wrappedValue.next.label) mode")
    }

    // MARK: - Brand block

    private var brandBlock: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            Image(bundled: "shamrock")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: isCompact ? 30 : 40, height: isCompact ? 30 : 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("NAGA CONFIGURATOR")
                    .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                if !isStacked {
                    Text(Device.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                        .fixedSize()
                }
                // The attribution line is the widest text in this block by far — only room for
                // it once the bar is at its full, uncompressed width.
                if !isCompact {
                    Text("Brought to you by MkrLab.io — a Jorivan LLC company")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.faint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            if !isCompact {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(hid.connected ? Theme.accent : Theme.muted)
                            .frame(width: 6, height: 6)
                        Text(hid.connected ? "Live" : "Disconnected")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.muted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text("Layer: \(hid.activeLayer.label)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.leading, 12)
                .overlay(Rectangle().fill(Theme.border).frame(width: 1), alignment: .leading)
            } else {
                Circle()
                    .fill(hid.connected ? Theme.accent : Theme.muted)
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Layer pills

    private var layerPills: some View {
        HStack(spacing: 2) {
            ForEach(HyperLayer.allCases, id: \.self) { layer in
                Button(isCompact ? compactLayerLabel(layer) : layer.label) { editLayer = layer }
                    .buttonStyle(PillButtonStyle(active: layer == editLayer))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(2)
        .background(Theme.bg)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Theme.border, lineWidth: 1))
        .cornerRadius(999)
        .fixedSize()
    }

    // MARK: - Nav tabs

    private var navTabs: some View {
        HStack(spacing: 2) {
            ForEach(NAV_TABS, id: \.self) { tab in
                Button {
                    activeTab = tab
                } label: {
                    if isCompact {
                        Image(systemName: NAV_TAB_ICONS[tab] ?? "circle")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 16, height: 16)
                    } else {
                        Text(tab.uppercased())
                    }
                }
                .buttonStyle(PillButtonStyle(active: tab == activeTab, uppercase: !isCompact))
                .help(tab)
                .lineLimit(1)
                .fixedSize()
            }
        }
        .fixedSize()
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button(action: onSave) {
            Text(saveState == .saving ? "Saving…" : saveState == .saved ? "Saved ✓" : "Save")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(width: isCompact ? 72 : 96)
        }
        .buttonStyle(SaveButtonStyle(saveState: saveState))
        .disabled(saveState != .dirty)
    }
}

struct PillButtonStyle: ButtonStyle {
    let active: Bool
    var uppercase = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, uppercase ? 14 : 12)
            .padding(.vertical, uppercase ? 6 : 4)
            .foregroundColor(active ? Color.black : Theme.muted)
            .background(active ? Theme.accent : Color.clear)
            .cornerRadius(999)
    }
}

struct SaveButtonStyle: ButtonStyle {
    let saveState: SaveState
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .foregroundColor(saveState == .dirty ? Color.black : Theme.muted)
            .background(saveState == .dirty ? Theme.accent : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(saveState == .dirty ? Color.clear : Theme.border, lineWidth: 1)
            )
            .cornerRadius(999)
            .opacity(saveState == .saving ? 0.6 : 1)
    }
}
