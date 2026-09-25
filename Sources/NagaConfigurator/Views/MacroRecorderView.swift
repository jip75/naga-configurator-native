import SwiftUI
import AppKit

struct MacroRecorderView: View {
    let value: Action?
    let onChange: (Action) -> Void

    @State private var recording = false
    @State private var steps: [MacroStep] = []
    @State private var monitor: Any?
    @State private var lastTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggleRecording) {
                Text(recording ? "Recording… press keys, click again to stop" : "Click to record a macro")
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .background(recording ? Theme.accent.opacity(0.12) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(recording ? Theme.accent : Theme.border, lineWidth: 1))
            .cornerRadius(8)

            if !steps.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack {
                            Text("\(i + 1). \(Keycodes.flagsLabel(step.flags))\(Keycodes.vkLabel(step.keyCode))" + (step.delayMs.map { " +\($0)ms" } ?? ""))
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            if !recording {
                                Button("✕") { removeStep(i) }
                                    .buttonStyle(.plain)
                                    .foregroundColor(Theme.muted)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .onAppear { steps = value?.steps ?? [] }
        .onDisappear { stopMonitoring(commit: false) }
    }

    private func toggleRecording() {
        if recording { stopMonitoring(commit: true); return }
        steps = []
        lastTime = Date()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !Keycodes.modifierKeyCodes.contains(event.keyCode) else { return nil }
            var flags: [ModifierFlag] = []
            if event.modifierFlags.contains(.command) { flags.append(.cmd) }
            if event.modifierFlags.contains(.shift) { flags.append(.shift) }
            if event.modifierFlags.contains(.control) { flags.append(.ctrl) }
            if event.modifierFlags.contains(.option) { flags.append(.option) }
            let now = Date()
            let delayMs = steps.isEmpty ? nil : min(Int(now.timeIntervalSince(lastTime) * 1000), 2000)
            lastTime = now
            steps.append(MacroStep(keyCode: Int(event.keyCode), flags: flags.isEmpty ? nil : flags, delayMs: delayMs))
            return nil
        }
    }

    private func stopMonitoring(commit: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        // Stopping before any key was pressed must not save an empty macro — it would show as a
        // normal-looking "Macro (0 steps)" that silently does nothing on every press.
        if commit && !steps.isEmpty { onChange(.macro(steps)) }
    }

    private func removeStep(_ i: Int) {
        steps.remove(at: i)
        onChange(.macro(steps))
    }
}
