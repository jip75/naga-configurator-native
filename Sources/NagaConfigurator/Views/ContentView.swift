import SwiftUI

enum SaveState { case clean, dirty, saving, saved }

let NAV_TABS = ["Customize", "Performance", "Scrolling", "Lighting", "About", "How-To"]

// Nothing beyond button-mapping is wired to real hardware state yet (no DPI/polling or Chroma
// telemetry) — these tabs switch for real, but show an honest "not yet configurable" state
// instead of fake controls. No Power tab: this is a wired mouse, no battery to manage.
let NAV_TAB_COPY: [String: String] = [
    "Performance": "DPI and polling-rate controls aren't wired to the hardware yet — button mapping is the only live feature so far.",
    "Scrolling": "Scroll-wheel tuning isn't wired to the hardware yet.",
    "Lighting": "Chroma lighting isn't wired up yet — the mouse keeps whatever RGB profile is already on it.",
]

struct ContentView: View {
    @EnvironmentObject var hid: NagaHIDManager
    @State private var mapping: ButtonMapping = MappingStore.load()
    @State private var selected: Int?
    @State private var selectedTop: String?
    @State private var editLayer: HyperLayer = .base
    @State private var activeTab = "Customize"
    @State private var saveState: SaveState = .clean
    @State private var diagramView: DiagramView = .top

    var body: some View {
        // GeometryReader here is the single source of truth for "how wide is the window right
        // now" — it receives that proposal directly from the window (via the App's
        // .frame(minWidth:...)), independent of anything TopBarView's own content wants to be.
        // We thread geo.size.width down to TopBarView explicitly instead of letting it
        // self-measure, and we pin the VStack to geo.size so an overflowing child can't inflate
        // this container's own reported size and defeat the measurement.
        GeometryReader { geo in
            VStack(spacing: 0) {
                TopBarView(
                    containerWidth: geo.size.width,
                    saveState: saveState,
                    onSave: save,
                    editLayer: $editLayer,
                    activeTab: $activeTab
                )
                .environmentObject(hid)

                Group {
                    if activeTab == "Customize" {
                        // Linearly scaled between the window's enforced minimum (620x640) and a
                        // "comfortable" size — guarantees the diagram row and its padding always
                        // sum to exactly what's available (see MouseDiagramView's own lerp for the
                        // matching math), instead of clipping at the smallest window size.
                        let hPad = lerp(16, 40, t: unitLerp(geo.size.width, from: 620, to: 900))
                        let vPad = lerp(14, 40, t: unitLerp(geo.size.height, from: 640, to: 860))
                        let vSpacing = lerp(10, 16, t: unitLerp(geo.size.height, from: 640, to: 860))

                        GeometryReader { area in
                            VStack(spacing: vSpacing) {
                                ZStack(alignment: .trailing) {
                                    if selected != nil || selectedTop != nil {
                                        // Click-away dismiss: a full-bleed transparent catcher BEHIND
                                        // the diagram — ZStack hit-testing gives later/topmost children
                                        // priority, so this must render under MouseDiagramView or it
                                        // swallows every tap on the diagram (including the other two
                                        // hotspots) once any panel is open, before the hotspot's own
                                        // onTapGesture ever sees it. Non-hotspot diagram areas (the
                                        // mouse image itself) have no gesture of their own, so taps
                                        // there still fall through to this catcher and dismiss.
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .onTapGesture { selected = nil; selectedTop = nil }
                                    }

                                    MouseDiagramView(
                                        view: diagramView,
                                        selected: hid.lastFiredButton ?? selected,
                                        selectedTop: selectedTop,
                                        mapping: layerMapping,
                                        editLayer: editLayer,
                                        activeLayer: hid.activeLayer,
                                        containerSize: CGSize(width: area.size.width, height: area.size.height - viewAngleStripHeight - vSpacing)
                                    ) { n in
                                        hid.debugLog("onSelect: number=\(n) (was selected=\(String(describing: selected)) selectedTop=\(String(describing: selectedTop)))")
                                        selectedTop = nil; selected = n
                                    } onSelectTop: { code in
                                        hid.debugLog("onSelectTop: rawCode=\(code) (was selected=\(String(describing: selected)) selectedTop=\(String(describing: selectedTop)))")
                                        selected = nil; selectedTop = code
                                    }
                                    .frame(maxWidth: .infinity)

                                    if selected != nil || selectedTop != nil {
                                        SidePanelView(
                                            buttonNumber: selected,
                                            topLabel: selectedTop.map(topButtonLabel),
                                            rawCode: selectedTop,
                                            action: selectedAction,
                                            editLayer: editLayer,
                                            onChange: handleActionChange,
                                            onClose: { selected = nil; selectedTop = nil }
                                        )
                                        // A different button or a different layer for the same
                                        // button must be a fresh SidePanelView instance — its
                                        // internal @State (typed label, rail selection) is seeded
                                        // once at init from `action` and must never be reused
                                        // across a different button, or a stale in-flight label
                                        // edit can land on the wrong one. See SidePanelView.init.
                                        .id("\(selectedRawCode ?? "")|\(editLayer.rawValue)")
                                        .padding(.trailing, 8)
                                        .transition(.move(edge: .trailing).combined(with: .opacity))
                                        .zIndex(1)
                                    }
                                }
                                .animation(.easeOut(duration: 0.22), value: selected)
                                .animation(.easeOut(duration: 0.22), value: selectedTop)

                                ViewAngleThumbnailsView(selection: $diagramView)
                            }
                        }
                        .padding(.horizontal, hPad)
                        .padding(.bottom, vPad)
                    } else if activeTab == "About" {
                        AboutView()
                    } else if activeTab == "How-To" {
                        HowToView()
                    } else {
                        Text(NAV_TAB_COPY[activeTab] ?? "")
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Theme.muted)
                            .padding(20)
                            .frame(maxWidth: 420)
                            .background(Theme.panel)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
                            .cornerRadius(16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .foregroundColor(Theme.fg)
        .background(Theme.bg)
        .onAppear {
            // Each layer stands on its own (no fallback to base) — same rule as the Electron
            // app's NagaBridge.handleLine.
            hid.onButtonPressed = { rawCode in
                hid.debugLog("onButtonPressed: rawCode=\(rawCode) activeLayer=\(hid.activeLayer) entry=\(String(describing: mapping[rawCode]))")
                if let action = mapping[rawCode]?.action(for: hid.activeLayer) {
                    hid.dispatch(action)
                } else {
                    hid.debugLog("onButtonPressed: no action resolved for rawCode=\(rawCode)")
                }
            }
        }
    }

    private var layerMapping: [String: Action?] {
        var resolved: [String: Action?] = [:]
        for (code, entry) in mapping {
            resolved[code] = entry.action(for: editLayer)
        }
        return resolved
    }

    private var selectedButton: ButtonPosition? {
        guard let selected else { return nil }
        return Device.buttons.first { $0.number == selected }
    }

    /// rawCode currently being edited, whether it's one of the 12 numbered buttons or one of the
    /// two top buttons flanking the wheel.
    private var selectedRawCode: String? {
        selectedButton?.rawCode ?? selectedTop
    }

    private func topButtonLabel(_ rawCode: String) -> String {
        switch rawCode {
        case "topA": return "Front Top Button"
        case "topB": return "Rear Top Button"
        case "scrollClick": return "Scroll Click"
        case "tiltLeft": return "Wheel Tilt Left"
        case "tiltRight": return "Wheel Tilt Right"
        default: return rawCode
        }
    }

    private var selectedAction: Action? {
        guard let selectedRawCode else { return nil }
        return mapping[selectedRawCode]?.action(for: editLayer)
    }

    private func handleActionChange(_ action: Action) {
        guard let selectedRawCode else { return }
        let entry = mapping[selectedRawCode] ?? ButtonEntry(base: action)
        mapping[selectedRawCode] = entry.setting(action, for: editLayer)
        saveState = .dirty
    }

    private func save() {
        guard saveState == .dirty else { return }
        saveState = .saving
        MappingStore.save(mapping)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            saveState = .saved
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                saveState = .clean
            }
        }
    }
}
