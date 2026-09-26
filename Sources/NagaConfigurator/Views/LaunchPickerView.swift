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

            pickerButton("Browse Applications…", action: browse)
            pickerButton("Choose a File to Open or Run…", action: browseFile)

            Text("Apps open normally. Scripts and other executables run directly; any other file opens in its default app.")
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
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

    private func pickerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .cornerRadius(8)
    }

    /// Any file at all — a shell script, a .command, a document. Stored as a full path in the same
    /// `appName` field launches already use, so mapping.json stays the same shape; dispatch tells
    /// "run it" from "open it" at press time (see NagaHIDManager.dispatch's .launch case).
    private func browseFile() {
        let panel = NSOpenPanel()
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            onChange(.launch(url.path))
            syncText()
        }
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
