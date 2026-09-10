import SwiftUI
import AppKit

struct LaunchPickerView: View {
    let value: Action?
    let onChange: (Action) -> Void

    @State private var text = ""

    var body: some View {
        VStack(spacing: 8) {
            TextField("Application name (e.g. Mission Control)", text: $text, onCommit: commit)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .cornerRadius(8)
                .onSubmit(commit)

            Button("Browse Applications…", action: browse)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .cornerRadius(8)
        }
        .onAppear { syncText() }
        .onChange(of: value) { _ in syncText() }
    }

    private func syncText() {
        guard let appName = value?.appName else { text = ""; return }
        let base = appName.split(separator: "/").last.map(String.init) ?? appName
        text = base.hasSuffix(".app") ? String(base.dropLast(4)) : base
    }

    private func commit() {
        onChange(.launch(text))
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            onChange(.launch(url.path))
            syncText()
        }
    }
}
