// © Pexilim
import BlinkKit
import SwiftUI

/// Every mood side by side with a picker, so the eye states can be approved on screen.
struct EyesPreview: View {
    @State private var mood = Mood.idle
    @State private var blinks = 0

    var body: some View {
        Form {
            Section {
                BlinkEyes(mood: mood, blinkTrigger: blinks)
                    .frame(height: 150)
                    .frame(maxWidth: 300)
                    .frame(maxWidth: .infinity)
                    .background(.black, in: .rect(cornerRadius: 22, style: .continuous))
                    .onTapGesture { blinks += 1 }
                    .accessibilityAction(named: "Blink") { blinks += 1 }
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Tap the eyes to blink. Resting blinks on its own every 20–40 s.")
            }
            Section {
                Picker("Mood", selection: $mood) {
                    ForEach(Mood.allCases) { Text($0.word).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Blink's eyes")
    }
}
