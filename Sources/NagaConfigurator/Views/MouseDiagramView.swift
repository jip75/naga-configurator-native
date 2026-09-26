import SwiftUI

enum DiagramView: CaseIterable { case top, side }

/// A control on top of the mouse (everything except the 12 side buttons). All are ordinary
/// customizable buttons on the same mapping/dispatch pipeline as 1-12. The wheel, tilts and the
/// two main clicks keep their built-in behavior no matter what (exclusive HID access to suppress it
/// is a confirmed dead end on this OS — see NagaHIDManager's header comment), so anything assigned
/// to them fires IN ADDITION to that; the `info` tooltips say so.
private struct TopControl {
    let rawCode: String
    let fallbackLabel: String
    let info: String
    /// Percent of the fitted top-view image rect — lands on the real control at any window size.
    let xy: (Double, Double)
    /// Which label column it lives in, and which row (0 = top) of that column.
    let onLeft: Bool
    let row: Int
}

// Measured off naga-left-handed-top.png (676x1250). Layout mirrors Synapse's top view: labels
// out in two columns, a thin leader line from each label to its control.
private let topControls: [TopControl] = [
    TopControl(rawCode: "leftClick", fallbackLabel: "Left Click",
               info: "Left click. Its normal click always happens — anything you assign here fires in addition to it. Never fires while this app is in front, so you can always click your way back here to fix it.",
               xy: (35, 25), onLeft: true, row: 0),
    TopControl(rawCode: "tiltLeft", fallbackLabel: "Repeat Scroll Left",
               info: "Wheel tilt left. By default it scrolls left (repeats while held). Anything you assign here fires in addition to that.",
               xy: (50, 30), onLeft: true, row: 2),
    TopControl(rawCode: "topA", fallbackLabel: "Unassigned",
               info: "Front button behind the wheel. Defaults to toggling the HyperShift layer. Also shifts cursor speed via the mouse's own firmware, which this app can't change.",
               xy: (55, 41.5), onLeft: true, row: 3),
    TopControl(rawCode: "topB", fallbackLabel: "Unassigned",
               info: "Rear button behind the wheel. Also shifts cursor speed via the mouse's own firmware, which this app can't change.",
               xy: (55, 47.6), onLeft: true, row: 4),
    TopControl(rawCode: "rightClick", fallbackLabel: "Right Click",
               info: "Right click. Its normal click always happens — anything you assign here fires in addition to it. Never fires while this app is in front, so you can always click your way back here to fix it.",
               xy: (76, 25), onLeft: false, row: 0),
    TopControl(rawCode: "scrollClick", fallbackLabel: "Scroll Click",
               info: "Pressing the wheel. Its normal middle-click always happens — anything you assign here fires in addition to it.",
               xy: (55, 34), onLeft: false, row: 2),
    TopControl(rawCode: "tiltRight", fallbackLabel: "Repeat Scroll Right",
               info: "Wheel tilt right. By default it scrolls right (repeats while held). Anything you assign here fires in addition to that.",
               xy: (60, 30), onLeft: false, row: 1),
]

private let topImageSize = CGSize(width: 676, height: 1250)

/// Aspect-fit rect of an image of `imageSize` inside `container` — mirrors what
/// `.aspectRatio(contentMode: .fit)` does, so overlay points can target the art itself.
private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
    let scale = min(container.width / imageSize.width, container.height / imageSize.height)
    let w = imageSize.width * scale, h = imageSize.height * scale
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

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
    private var tint: Color { Theme.layerTint(editLayer) }

    // Scales continuously between a "tight" layout that exactly fits the window's enforced
    // minimum (620x640) and a "comfortable" one. Anchors are the actual containerSize this view
    // receives at 620x640 and at 900x860 (see ContentView's matching lerp).
    private var wt: CGFloat { unitLerp(containerSize.width, from: 588, to: 820) }
    private var ht: CGFloat { unitLerp(containerSize.height, from: 430, to: 634) }
    // Columns take whatever width the art and gaps leave (capped) — fixed widths truncated
    // labels like "Mission Control" to "Mission…" while ~170pt sat unused at the window edges.
    private var columnWidth: CGFloat { min(200, max(92, (containerSize.width - centerWidth - 2 * rowSpacing) / 2 - 8)) }
    private var rowSpacing: CGFloat { lerp(28, 48, t: wt) }
    private var centerWidth: CGFloat { lerp(170, 240, t: wt) }
    private var diagramHeight: CGFloat { lerp(320, 420, t: ht) }
    private var labelFont: CGFloat { lerp(11, 13, t: wt) }
    private var badgeSize: CGFloat { lerp(24, 28, t: wt) }
    private var vPadding: CGFloat { lerp(16, 24, t: ht) }

    var body: some View {
        Group {
            if view == .top { topLayout } else { sideLayout }
        }
        .padding(.vertical, vPadding)
    }

    // MARK: Side view — the 12 side buttons, columns set well clear of the art.

    private var sideLayout: some View {
        HStack(spacing: rowSpacing) {
            VStack(alignment: .trailing, spacing: lerp(12, 20, t: ht)) {
                ForEach(left) { b in
                    ButtonLabelView(number: b.number, action: mapping[b.rawCode] ?? nil, active: selected == b.number, align: .trailing, labelFont: labelFont, badgeSize: badgeSize, tint: tint, onSelect: { onSelect(b.number) })
                }
            }
            .frame(width: columnWidth)

            GeometryReader { geo in
                ZStack {
                    Image(bundled: "naga-left-handed-cutout")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: tint.opacity(0.5), radius: 8)
                        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                    ForEach(Device.buttons) { b in
                        HotspotView(active: selected == b.number)
                            .position(x: geo.size.width * b.x / 100, y: geo.size.height * b.y / 100)
                            .onTapGesture { onSelect(b.number) }
                    }
                }
            }
            .frame(width: centerWidth, height: diagramHeight)

            VStack(alignment: .leading, spacing: lerp(12, 20, t: ht)) {
                ForEach(right) { b in
                    ButtonLabelView(number: b.number, action: mapping[b.rawCode] ?? nil, active: selected == b.number, align: .leading, labelFont: labelFont, badgeSize: badgeSize, tint: tint, onSelect: { onSelect(b.number) })
                }
            }
            .frame(width: columnWidth)
        }
    }

    // MARK: Top view — top controls only, label columns + leader lines (Synapse-style).

    private var topLayout: some View {
        GeometryReader { geo in
            let artBox = CGSize(width: centerWidth, height: diagramHeight)
            let artOrigin = CGPoint(x: (geo.size.width - artBox.width) / 2, y: 0)
            let r0 = fittedRect(imageSize: topImageSize, in: artBox)
            let img = r0.offsetBy(dx: artOrigin.x, dy: artOrigin.y)
            let gap: CGFloat = lerp(34, 56, t: wt)       // label anchor dot → edge of the art
            let rowH = diagramHeight * 0.115
            let firstRow = diagramHeight * 0.14

            ZStack(alignment: .topLeading) {
                Image(bundled: "naga-left-handed-top")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: tint.opacity(0.5), radius: 8)
                    .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                    .frame(width: artBox.width, height: artBox.height)
                    .offset(x: artOrigin.x)

                ForEach(topControls, id: \.rawCode) { c in
                    let target = CGPoint(x: img.minX + img.width * c.xy.0 / 100, y: img.minY + img.height * c.xy.1 / 100)
                    let anchor = CGPoint(x: c.onLeft ? img.minX - gap : img.maxX + gap, y: firstRow + rowH * CGFloat(c.row))
                    let elbow = CGPoint(x: c.onLeft ? img.minX - gap * 0.35 : img.maxX + gap * 0.35, y: anchor.y)
                    let assigned = mapping[c.rawCode] ?? nil
                    let isSelected = selectedTop == c.rawCode
                    let engaged = isSelected || (assigned?.kind == .layerToggle && assigned?.targetLayer != nil &&
                                                 (assigned?.targetLayer == activeLayer || assigned?.targetLayer == editLayer))

                    Path { p in p.move(to: anchor); p.addLine(to: elbow); p.addLine(to: target) }
                        .stroke(tint.opacity(isSelected ? 0.95 : 0.55), lineWidth: isSelected ? 1.5 : 1)
                    Circle().fill(tint.opacity(0.9)).frame(width: 4, height: 4).position(anchor)
                    Circle().fill(tint).frame(width: 5, height: 5).position(target)

                    Text(assigned?.displayLabel ?? c.fallbackLabel)
                        .font(.system(size: labelFont, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(engaged || isSelected ? tint : (assigned != nil ? tint.opacity(0.85) : Theme.muted))
                        .lineLimit(1)
                        .frame(width: 170, alignment: c.onLeft ? .trailing : .leading)
                        .position(x: c.onLeft ? anchor.x - 10 - 85 : anchor.x + 10 + 85, y: anchor.y)
                        .contentShape(Rectangle())
                        .help(c.info)
                        .onTapGesture { onSelectTop(c.rawCode) }
                    Color.clear.frame(width: 26, height: 26).contentShape(Rectangle())
                        .position(target).help(c.info)
                        .onTapGesture { onSelectTop(c.rawCode) }
                }
            }
        }
        .frame(height: diagramHeight)
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
    var tint: Color = Theme.accent
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
            .background(active ? tint : Color.white.opacity(0.08))
            .overlay(Circle().stroke(active ? tint : Theme.border, lineWidth: 1))
            .clipShape(Circle())
    }

    private var label: some View {
        Text(action?.displayLabel ?? "Unassigned")
            .font(.system(size: labelFont, weight: .medium))
            .foregroundColor(active ? tint : (action != nil ? tint.opacity(0.9) : Theme.muted))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
    }
}
