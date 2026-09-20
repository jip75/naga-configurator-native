import SwiftUI

enum DiagramView: CaseIterable { case top, side }

/// A control that exists on the mouse but isn't part of the 12-button left/right column layout.
/// All three are now plain customizable buttons (rawCode "scrollClick"/"topA"/"topB", same
/// mapping/dispatch pipeline as 1-12), so their `rawCode` is non-nil and their displayed label
/// comes from whatever action is actually assigned, not a fixed string. Scroll Click is the one
/// exception worth flagging in its `info` tooltip: exclusive HID device access is a confirmed
/// dead end on this OS (see NagaHIDManager's header comment), so the wheel-click's standard
/// system middle-click keeps firing on top of whatever custom action gets assigned here — same
/// honest-about-limits spirit as NAV_TAB_COPY, just "both fire" instead of "not configurable".
private struct SystemHotspot {
    let fallbackLabel: String
    let info: String
    let rawCode: String?
    let topXY: (Double, Double)
    let sideXY: (Double, Double)
    var labelOnLeft: Bool = false

    func xy(for view: DiagramView) -> (Double, Double) { view == .top ? topXY : sideXY }
}

private let systemHotspots: [SystemHotspot] = [
    SystemHotspot(
        fallbackLabel: "Scroll Click",
        info: "Customizable, same as buttons 1-12. The wheel's standard system middle-click also keeps firing alongside whatever you assign here — that part can't be intercepted from software.",
        rawCode: "scrollClick",
        topXY: (48, 14), sideXY: (33, 6)
    ),
    SystemHotspot(
        fallbackLabel: "Unassigned",
        info: "Front button behind the wheel — customizable, same as buttons 1-12. Defaults to toggling the HyperShift layer. Also shifts cursor speed via the mouse's own onboard firmware, independent of this app — not something this app can change or turn off.",
        rawCode: "topA",
        topXY: (48, 25.5), sideXY: (33, 17)
    ),
    SystemHotspot(
        fallbackLabel: "Unassigned",
        info: "Rear button behind the wheel — customizable, same as buttons 1-12. Also shifts cursor speed via the mouse's own onboard firmware, independent of this app — not something this app can change or turn off.",
        rawCode: "topB",
        topXY: (48, 37), sideXY: (33, 29)
    ),
    // "bottomButton" hotspot removed 2026-09-11 — usage 0x09/0x02 turned out to be this mouse's
    // ordinary secondary click, not a distinct physical control. See Action.swift's DefaultMapping
    // and NagaHIDManager's dpiUsageToRawCode comments.
    SystemHotspot(
        fallbackLabel: "Unassigned",
        info: "Wheel tilt left — customizable, same as buttons 1-12. The mouse's own default horizontal-scroll behavior also keeps firing alongside whatever you assign here — that part can't be intercepted from software, same as Scroll Click.",
        rawCode: "tiltLeft",
        topXY: (40, 5), sideXY: (24, 1),
        labelOnLeft: true
    ),
    SystemHotspot(
        fallbackLabel: "Unassigned",
        info: "Wheel tilt right — customizable, same as buttons 1-12. The mouse's own default horizontal-scroll behavior also keeps firing alongside whatever you assign here — that part can't be intercepted from software, same as Scroll Click.",
        rawCode: "tiltRight",
        topXY: (57, 5), sideXY: (42, 1)
    ),
]

struct MouseDiagramView: View {
    let view: DiagramView
    let selected: Int?
    let selectedTop: String?
    let mapping: [String: Action?]
    let editLayer: HyperLayer
    let activeLayer: HyperLayer
    let containerSize: CGSize
    let onSelect: (Int) -> Void
    let onSelectTop: (String) -> Void

    private var left: [ButtonPosition] { Device.buttons.filter { $0.number <= 6 } }
    private var right: [ButtonPosition] { Device.buttons.filter { $0.number > 6 } }
    private var imageName: String { view == .top ? "naga-left-handed-top" : "naga-left-handed-cutout" }
    private var caption: String { view == .top ? "TOP VIEW" : "SIDE VIEW" }

    // Scales continuously between a "tight" layout that exactly fits the window's enforced
    // minimum (620x640) and a "comfortable" layout, using the same from/to anchors ContentView
    // uses for its own padding — so the row's total width/height always equals what's actually
    // available instead of a fixed size that clips below ~708x600.
    // Anchors are the actual containerSize this view receives at the window's enforced minimum
    // (620x640, worked out from TopBarView/ViewAngleThumbnailsView's real heights) and at a taller
    // 900x860 window — not arbitrary round numbers — so `diagramHeight`+`vPadding`*2 never exceeds
    // what ContentView actually handed us, at either end.
    private var wt: CGFloat { unitLerp(containerSize.width, from: 588, to: 820) }
    private var ht: CGFloat { unitLerp(containerSize.height, from: 430, to: 634) }
    private var columnWidth: CGFloat { lerp(92, 160, t: wt) }
    private var rowSpacing: CGFloat { lerp(12, 24, t: wt) }
    private var centerWidth: CGFloat { lerp(180, 260, t: wt) }
    private var diagramHeight: CGFloat { lerp(320, 420, t: ht) }
    private var labelFont: CGFloat { lerp(11, 13, t: wt) }
    private var badgeSize: CGFloat { lerp(24, 28, t: wt) }
    private var vPadding: CGFloat { lerp(16, 24, t: ht) }

    var body: some View {
        HStack(spacing: rowSpacing) {
            VStack(alignment: .trailing, spacing: lerp(12, 20, t: ht)) {
                ForEach(left) { b in
                    ButtonLabelView(number: b.number, action: mapping[b.rawCode] ?? nil, active: selected == b.number, align: .trailing, labelFont: labelFont, badgeSize: badgeSize, onSelect: { onSelect(b.number) })
                }
            }
            .frame(width: columnWidth)

            ZStack {
                GeometryReader { geo in
                    ZStack {
                        Image(bundled: imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .shadow(color: Theme.accent.opacity(0.5), radius: 8)
                            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)

                        ForEach(view == .top ? Device.topButtons.map { ($0.number, $0.x, $0.y) } : Device.buttons.map { ($0.number, $0.x, $0.y) }, id: \.0) { number, x, y in
                            HotspotView(active: selected == number)
                                .position(x: geo.size.width * x / 100, y: geo.size.height * y / 100)
                                .onTapGesture { onSelect(number) }
                        }

                        ForEach(Array(systemHotspots.enumerated()), id: \.offset) { _, spot in
                            let (x, y) = spot.xy(for: view)
                            let assigned = spot.rawCode.flatMap { mapping[$0] ?? nil }
                            let engaged = spot.rawCode != nil && (
                                selectedTop == spot.rawCode ||
                                (assigned?.kind == .layerToggle && assigned?.targetLayer != nil &&
                                 (assigned?.targetLayer == activeLayer || assigned?.targetLayer == editLayer))
                            )
                            SystemHotspotLabel(text: assigned?.displayLabel ?? spot.fallbackLabel, engaged: engaged, alignLeading: !spot.labelOnLeft)
                                .frame(width: 100, alignment: spot.labelOnLeft ? .trailing : .leading)
                                .contentShape(Rectangle())
                                .position(x: geo.size.width * x / 100 + (spot.labelOnLeft ? -58 : 58), y: geo.size.height * y / 100)
                                .onTapGesture { if let code = spot.rawCode { onSelectTop(code) } }
                            SystemHotspotDot(engaged: engaged)
                                .contentShape(Rectangle())
                                .position(x: geo.size.width * x / 100 + (spot.labelOnLeft ? 38 : -38), y: geo.size.height * y / 100)
                                .help(spot.info)
                                .onTapGesture { if let code = spot.rawCode { onSelectTop(code) } }
                        }
                    }
                }
                .frame(height: diagramHeight)

                Text(caption)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.muted)
                    .offset(y: -(diagramHeight / 2) + 10)
            }
            .frame(width: centerWidth, height: diagramHeight)

            VStack(alignment: .leading, spacing: lerp(12, 20, t: ht)) {
                ForEach(right) { b in
                    ButtonLabelView(number: b.number, action: mapping[b.rawCode] ?? nil, active: selected == b.number, align: .leading, labelFont: labelFont, badgeSize: badgeSize, onSelect: { onSelect(b.number) })
                }
            }
            .frame(width: columnWidth)
        }
        .padding(.vertical, vPadding)
    }
}

/// A small view-angle thumbnail strip (Synapse shows this row under the mouse illustration) —
/// exactly the 2 angles this app has real art for: top-down and the side-angle cutout. Sized up
/// from the original 44pt icons for legibility — this is the row users kept missing/mis-tapping.
struct ViewAngleThumbnailsView: View {
    @Binding var selection: DiagramView

    private func imageName(for angle: DiagramView) -> String {
        angle == .top ? "naga-left-handed-top" : "naga-left-handed-cutout"
    }
    private func caption(for angle: DiagramView) -> String {
        angle == .top ? "Top View" : "Side View"
    }

    var body: some View {
        HStack(spacing: 16) {
            ForEach(DiagramView.allCases, id: \.self) { angle in
                Button { selection = angle } label: {
                    VStack(spacing: 8) {
                        Image(bundled: imageName(for: angle))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .padding(8)
                            .background(Theme.bg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selection == angle ? Theme.accent : Theme.border, lineWidth: selection == angle ? 2.5 : 1)
                            )
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(selection == angle ? 0.28 : 0.12), radius: selection == angle ? 10 : 4, x: 0, y: 3)
                        Text(caption(for: angle))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(selection == angle ? Theme.accentText : Theme.muted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SystemHotspotDot: View {
    let engaged: Bool
    var body: some View {
        Circle()
            .strokeBorder(engaged ? Theme.accent : Theme.muted, lineWidth: 2)
            .background(Circle().fill(engaged ? Theme.accent.opacity(0.25) : Theme.bg))
            .frame(width: 13, height: 13)
            .shadow(color: engaged ? Theme.accentDim : .clear, radius: 4)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
    }
}

private struct SystemHotspotLabel: View {
    let text: String
    let engaged: Bool
    var alignLeading: Bool = true
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(engaged ? Theme.accentText : Theme.muted)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct HotspotView: View {
    let active: Bool
    var body: some View {
        Circle()
            .fill(active ? Theme.accent : Color.white.opacity(0.55))
            .frame(width: active ? 12 : 8, height: active ? 12 : 8)
            .shadow(color: active ? Theme.accentDim : .clear, radius: active ? 4 : 0)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }
}

struct ButtonLabelView: View {
    let number: Int
    let action: Action?
    let active: Bool
    let align: HorizontalAlignment
    var labelFont: CGFloat = 13
    var badgeSize: CGFloat = 28
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if align == .leading { badge; label } else { label; badge }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var badge: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: badgeSize, height: badgeSize)
            .foregroundColor(active ? .black : Theme.fg)
            .background(active ? Theme.accent : Color.white.opacity(0.08))
            .overlay(Circle().stroke(active ? Theme.accent : Theme.border, lineWidth: 1))
            .clipShape(Circle())
    }

    private var label: some View {
        Text(action?.displayLabel ?? "Unassigned")
            .font(.system(size: labelFont, weight: .medium))
            .foregroundColor(active ? Theme.accentText : (action != nil ? Theme.fg : Theme.muted))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
    }
}
