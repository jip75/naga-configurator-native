import SwiftUI

struct MouseFunctionEditorView: View {
    let value: Action?
    let onChange: (Action) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(MouseButton.allCases, id: \.self) { opt in
                let selected = value?.button == opt
                Button(opt.label) { onChange(.mouse(opt)) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .foregroundColor(selected ? Theme.accent : Theme.fg)
                    .background(selected ? Theme.accent.opacity(0.12) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent : Theme.border, lineWidth: 1))
                    .cornerRadius(8)
            }
        }
    }
}
