import SwiftUI

private struct HowToStep {
    let number: Int
    let title: String
    let detail: String
}

private let STEPS: [HowToStep] = [
    HowToStep(number: 1, title: "Pick a button", detail: "On the Customize tab, click any numbered button or one of the two top buttons on the mouse diagram."),
    HowToStep(number: 2, title: "Assign an action", detail: "The side panel that opens lets you assign a keystroke, a mouse click, an app launch, or a multi-step macro to that button."),
    HowToStep(number: 3, title: "Switch layers for more", detail: "Use the Std / HS A / HS B pills at the top to edit a second and third action for the same button — HyperShift lets one button do three different things depending on which layer is active."),
    HowToStep(number: 4, title: "Check both view angles", detail: "Use the Top View / Side View thumbnails below the diagram to reach every button, including the ones on the side of the mouse."),
    HowToStep(number: 5, title: "Save", detail: "Click Save in the top bar once you're happy — nothing is written to disk until you do."),
]

struct HowToView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How to use this app")
                        .font(.system(size: 20, weight: .bold))
                    Text("A quick walkthrough of remapping a button.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                }

                VStack(spacing: 12) {
                    ForEach(STEPS, id: \.number) { step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(step.number)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color.black)
                                .frame(width: 24, height: 24)
                                .background(Theme.accent)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(step.detail)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panel)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
                        .cornerRadius(14)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
        }
    }
}
