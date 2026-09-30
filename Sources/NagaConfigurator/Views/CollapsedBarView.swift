import SwiftUI
import AppKit

/// Host-WiFi-Control-style collapse: the window shrinks to a slim always-on-top strip parked in
/// the top-right corner of the screen, and the chevron restores it to its previous frame.
final class CollapseState: ObservableObject {
    @Published var collapsed = false
    private var savedFrame: NSRect?
    private var savedLevel: NSWindow.Level = .normal

    static let size = CGSize(width: 300, height: 52)

    private var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.title == "Naga Configurator" } ?? NSApp.keyWindow
    }

    func toggle() {
        guard let w = window else { collapsed.toggle(); return }
        if !collapsed {
            savedFrame = w.frame
            savedLevel = w.level
            collapsed = true
            DispatchQueue.main.async {
                w.level = .floating
                let vis = (w.screen ?? NSScreen.main)?.visibleFrame ?? w.frame
                let h = Self.size.height + (w.frame.height - w.contentLayoutRect.height)
                let f = NSRect(x: vis.maxX - Self.size.width - 12, y: vis.maxY - h - 12,
                               width: Self.size.width, height: h)
                w.setFrame(f, display: true, animate: true)
            }
        } else {
            collapsed = false
            DispatchQueue.main.async {
                w.level = self.savedLevel
                if let f = self.savedFrame { w.setFrame(f, display: true, animate: true) }
            }
        }
    }
}

struct CollapsedBarView: View {
    @EnvironmentObject var hid: NagaHIDManager
    @EnvironmentObject var collapse: CollapseState

    var body: some View {
        HStack(spacing: 10) {
            Image(bundled: "shamrock")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(Circle())
            Text("NAGA")
                .font(.system(size: 12, weight: .semibold))
            Circle()
                .fill(hid.connected ? Theme.accent : Theme.muted)
                .frame(width: 6, height: 6)
            Text(hid.activeLayer.label)
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { collapse.toggle() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.muted)
            .help("Expand")
        }
        .padding(.horizontal, 12)
        .frame(width: CollapseState.size.width, height: CollapseState.size.height)
        .background(Theme.bg)
    }
}
