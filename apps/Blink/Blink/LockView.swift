// © Pexilim
import BlinkKit
import SwiftUI

struct LockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 20) {
            BlinkEyes(mood: .focus)
                .frame(width: 180, height: 100)
                .background(.black, in: .rect(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            Text("Blink is locked")
                .font(.title2.bold())
            Button("Unlock") { Task { await model.unlock() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.background)
        // Ask once each time the app comes to the front locked; Cancel leaves this screen up.
        .task(id: scenePhase) {
            if scenePhase == .active { await model.unlockIfPending() }
        }
    }
}

extension Color {
    /// `semantic.background` in design/tokens.json.
    static var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}
