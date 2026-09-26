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
    RailItem(id: "Launch", icon: "arrow.up.forward.app", tooltip: "Launch an App or File", kind: .launch),
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
    /// Set for the 12 numbered buttons; nil for the top/bottom system buttons.
    let buttonNumber: Int?
    /// Set for the top/bottom system buttons; nil for the 12 numbered buttons.
    let topLabel: String?
    /// The system button's rawCode ("topA"/"topB"/"bottomButton"); nil for the 12 numbered buttons.
    /// Distinct from `topLabel` because the HyperShift-assign lock below applies only to the two
    /// buttons flanking the wheel, not every system button.
    let rawCode: String?
    let action: Action?
    let editLayer: HyperLayer
    let onChange: (Action) -> Void
    let onClose: () -> Void

    @State private var railSelection: String
    @State private var labelText: String

    // ContentView gives this view a `.id()` keyed on (rawCode, editLayer), so a different button
    // or a different layer for the same button is a brand-new SidePanelView instance, not a reused
    // one — these initial values seed @State once, on that fresh instance, instead of being
    // written in via onAppear/onChange. That matters because `onChange(of: labelText)` below
    // commits straight to `onChange`/ContentView using whatever button is CURRENTLY selected —
    // if switching buttons re-set labelText on a still-alive instance instead of creating a new
    // one, that commit could land the outgoing button's label on the newly-selected button (this
    // is exactly what corrupted a HyperShift-locked label onto Button 12's neighbor live on
    // 2026-09-11). A fresh instance per identity makes that race structurally impossible.
    init(buttonNumber: Int?, topLabel: String?, rawCode: String?, action: Action?, editLayer: HyperLayer,
         onChange: @escaping (Action) -> Void, onClose: @escaping () -> Void) {
        self.buttonNumber = buttonNumber
        self.topLabel = topLabel
        self.rawCode = rawCode
        self.action = action
        self.editLayer = editLayer
        self.onChange = onChange
        self.onClose = onClose
        let locked = rawCode == "topA" && editLayer != .base
        _railSelection = State(initialValue: locked ? "HyperShift Assign" : (action.map { railID(for: $0.kind) } ?? "Keyboard Function"))
        _labelText = State(initialValue: action?.label ?? "")
    }

    private var isOpen: Bool { buttonNumber != nil || topLabel != nil }
    private var headerTitle: String { buttonNumber.map { "Button \($0)" } ?? topLabel ?? "" }
    // Under a HyperShift layer, topA exists only to toggle back out of that layer — Razer's own
    // Synapse locks it down to layer-assign once you're editing inside a HyperShift tab. Locking
    // here (not just defaulting) stops a HyperShift-layer press from silently landing on a stale
    // key/mouse/macro/launch action instead. topB and the bottom button are NOT part of this
    // toggle-back convention (confirmed live 2026-09-11: topB is meant to fire the same action —
    // Screenshot — on every layer, so it needs to stay editable/assignable under HS A/HS B too),
    // so the lock is scoped to topA alone by rawCode, not by topLabel != nil.
    private var isLockedToHyperShiftAssign: Bool { rawCode == "topA" && editLayer != .base }

    var body: some View {
        Group {
            if isOpen {
                HStack(spacing: 0) {
                    // Vertical icon rail
                    VStack(spacing: 4) {
                        ForEach(RAIL) { item in
                            let disabled = item.kind == nil || (isLockedToHyperShiftAssign && item.id != "HyperShift Assign")
                            Button {
                                guard !disabled else { return }
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
                            .opacity(disabled ? 0.35 : 1)
                            .help(isLockedToHyperShiftAssign && item.kind != nil && item.id != "HyperShift Assign"
                                  ? "Top buttons only toggle layers while editing \(editLayer.label) — switch to Standard to assign a shortcut"
                                  : item.tooltip)
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
                                // onCommit/onSubmit only fire on Return — clicking away from the
                                // field (the far more common way to finish typing a name) fired
                                // neither, so the label never reached `mapping` and Save never lit
                                // up. Commit on every keystroke instead; safe now that a fresh
                                // SidePanelView instance (see init) is what resets labelText when
                                // the selected button/layer changes, not a mutation of this one.
                                .onChange(of: labelText) { _ in commitLabel() }
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
        default: return "APP OR FILE"
        }
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
