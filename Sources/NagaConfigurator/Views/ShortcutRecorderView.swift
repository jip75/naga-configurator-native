import SwiftUI
import AppKit

/// Records the next key-down via a local NSEvent monitor while `recording` — the native
/// equivalent of the Electron app's onKeyDown handler, minus the browser KeyboardEvent.code
/// translation table (NSEvent.keyCode already IS the macOS virtual key code).
struct ShortcutRecorderView: View {
    let value: Action?
    let onChange: (Action) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            Text(recording ? "Press a key combo…" : (value.map { "\(Keycodes.flagsLabel($0.flags))\(Keycodes.vkLabel($0.keyCode ?? -1))" } ?? "Click to record a shortcut"))
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .buttonStyle(.plain)
        .background(recording ? Theme.accent.opacity(0.12) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(recording ? Theme.accent : Theme.border, lineWidth: 1))
        .cornerRadius(8)
        .onDisappear { stopMonitoring() }
    }

    private func toggleRecording() {
        if recording { stopMonitoring(); return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !Keycodes.modifierKeyCodes.contains(event.keyCode) else { return nil }
            var flags: [ModifierFlag] = []
            if event.modifierFlags.contains(.command) { flags.append(.cmd) }
            if event.modifierFlags.contains(.shift) { flags.append(.shift) }
            if event.modifierFlags.contains(.control) { flags.append(.ctrl) }
            if event.modifierFlags.contains(.option) { flags.append(.option) }
            onChange(.key(Int(event.keyCode), flags: flags))
            stopMonitoring()
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
