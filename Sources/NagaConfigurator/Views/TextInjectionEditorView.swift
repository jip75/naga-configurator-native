import SwiftUI

struct TextInjectionEditorView: View {
    let value: Action?
    let onChange: (Action) -> Void

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(Theme.bg)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .cornerRadius(8)
                .frame(minHeight: 80)
                .onChange(of: text) { newText in
                    onChange(.text(newText))
                }

            HStack {
                Text("Inject any text or special characters.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                Spacer()
                Text("\(text.count) chars")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accentText)
            }
        }
        .onAppear {
            text = value?.text ?? ""
        }
    }
}
