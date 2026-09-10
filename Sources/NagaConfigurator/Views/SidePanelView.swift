import SwiftUI

/// One rail entry. `kind` is non-nil only for the 4 real ActionKind editors this app can actually
/// save (matches Action.ActionKind exactly — key/mouse/macro/launch). HyperShift-assign and
/// profile-switch are shown in the rail because Synapse's reference screenshots show a rail this
/// size, but `kind == nil` for them: there's no ActionKind to back them, so they render disabled
/// with an honest tooltip instead of a fake editor — same "not wired up yet" pattern the rest of
/// this app already uses (see NAV_TAB_COPY in ContentView.swift).
private struct RailItem: Identifiable {
    let id: String
    let icon: String
    let tooltip: String
    let kind: ActionKind?
}

private let RAIL: [RailItem] = [
    RailItem(id: "Keyboard Function", icon: "keyboard", tooltip: "Keyboard Function", kind: .key),
    RailItem(id: "Mouse Function", icon: "computermouse", tooltip: "Mouse Function", kind: .mouse),
    RailItem(id: "Macro", icon: "record.circle", tooltip: "Macro", kind: .macro),
    RailItem(id: "Launch", icon: "arrow.up.forward.app", tooltip: "Launch App", kind: .launch),
    RailItem(id: "HyperShift Assign", icon: "bolt.fill", tooltip: "Toggle a HyperShift layer", kind: .layerToggle),
    RailItem(id: "Switch Profile", icon: "square.stack.3d.up", tooltip: "Switch Profile — not wired up yet (single profile only)", kind: nil),
]

private func railID(for kind: ActionKind) -> String {
    switch kind {
    case .key: return "Keyboard Function"
    case .mouse: return "Mouse Function"
    case .macro: return "Macro"
    case .launch: return "Launch"
    case .layerToggle: return "HyperShift Assign"
    }
}

/// The button editor — a slide-in panel docked to the right edge of the window (mirrors Synapse's
/// left-docked panel; we dock right since this whole app is the mirrored, left-handed take on
/// Synapse's right-handed reference UI), with a vertical icon rail down its own left edge for
/// switching action type, same layout language as the reference screenshots.
struct SidePanelView: View {
    /// Set for the 12 numbered buttons; nil for the two top buttons flanking the wheel.
    let buttonNumber: Int?
    /// Set for the two top buttons flanking the wheel; nil for the 12 numbered buttons.
    let topLabel: String?
    let action: Action?
    let editLayer: HyperLayer
    let onChange: (Action) -> Void
    let onClose: () -> Void

    @State private var railSelection = "Keyboard Function"
    @State private var labelText = ""

    private var isOpen: Bool { buttonNumber != nil || topLabel != nil }
    private var headerTitle: String { buttonNumber.map { "Button \($0)" } ?? topLabel ?? "" }

    var body: some View {
        Group {
            if isOpen {
                HStack(spacing: 0) {
                    // Vertical icon rail
                    VStack(spacing: 4) {
                        ForEach(RAIL) { item in
                            Button {
                                guard item.kind != nil else { return }
                                railSelection = item.id
                            } label: {
                                Image(systemName: item.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(railIconColor(item))
                            .background(railSelection == item.id ? Theme.accent.opacity(0.15) : Color.clear)
                            .cornerRadius(8)
                            .opacity(item.kind == nil ? 0.35 : 1)
                            .help(item.tooltip)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                    .frame(width: 56)
                    .background(Theme.bg)
                    .overlay(Rectangle().fill(Theme.border).frame(width: 1), alignment: .trailing)

                    // Editor content
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(headerTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.muted)
                                .tracking(0.5)
                            Spacer()
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Theme.muted)
                                    .frame(width: 22, height: 22)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Close")
                        }

                        HStack(spacing: 12) {
                            Group {
                                if let buttonNumber {
                                    Text("\(buttonNumber)")
                                        .font(.system(size: 13, weight: .bold))
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 13, weight: .bold))
                                }
                            }
                            .frame(width: 36, height: 36)
                            .background(Theme.accent)
                            .foregroundColor(.black)
                            .clipShape(Circle())

                            TextField("Name this button (optional)", text: $labelText, onCommit: commitLabel)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Theme.bg)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                                .cornerRadius(8)
                                .onSubmit(commitLabel)
                        }

                        Text(editLayer.label.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.accentText)
                            .tracking(1)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ASSIGNED \(assignedNoun)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.muted)
                                .tracking(0.5)

                            switch railSelection {
                            case "Keyboard Function":
                                ShortcutRecorderView(value: action?.kind == .key ? action : nil, onChange: onChange)
                            case "Mouse Function":
                                MouseFunctionEditorView(value: action?.kind == .mouse ? action : nil, onChange: onChange)
                            case "Macro":
                                MacroRecorderView(value: action?.kind == .macro ? action : nil, onChange: onChange)
                            case "HyperShift Assign":
                                LayerToggleEditorView(value: action?.kind == .layerToggle ? action : nil, onChange: onChange)
                            default:
                                LaunchPickerView(value: action?.kind == .launch ? action : nil, onChange: onChange)
                            }
                        }

                        Spacer()
                    }
                    .padding(20)
                }
                .frame(width: 340)
                .frame(maxHeight: .infinity)
                .background(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.4), radius: 24, x: -4, y: 8)
                .onAppear { syncFromAction() }
                .onChange(of: buttonNumber) { _ in syncFromAction() }
                .onChange(of: topLabel) { _ in syncFromAction() }
                .onChange(of: editLayer) { _ in syncFromAction() }
            } else {
                EmptyView()
            }
        }
    }

    private func railIconColor(_ item: RailItem) -> Color {
        guard item.kind != nil else { return Theme.muted }
        return railSelection == item.id ? Theme.accent : Theme.muted
    }

    private var assignedNoun: String {
        switch railSelection {
        case "Keyboard Function": return "SHORTCUT"
        case "Mouse Function": return "CLICK"
        case "Macro": return "SEQUENCE"
        case "HyperShift Assign": return "LAYER"
        default: return "APPLICATION"
        }
    }

    private func syncFromAction() {
        railSelection = action.map { railID(for: $0.kind) } ?? "Keyboard Function"
        labelText = action?.label ?? ""
    }

    private func commitLabel() {
        guard var current = action else { return }
        current.label = labelText
        onChange(current)
    }
}

/// Picks which HyperLayer this button toggles into (press again to return to Standard).
private struct LayerToggleEditorView: View {
    let value: Action?
    let onChange: (Action) -> Void

    private var selectedLayer: HyperLayer { value?.targetLayer ?? .hyperA }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([HyperLayer.hyperA, .hyperB], id: \.self) { layer in
                Button { onChange(.layerToggle(layer)) } label: {
                    HStack {
                        Text(layer.label)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        if selectedLayer == layer && value != nil {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(selectedLayer == layer && value != nil ? Theme.accent.opacity(0.15) : Theme.bg)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    .cornerRadius(8)
                    .foregroundColor(Theme.fg)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
