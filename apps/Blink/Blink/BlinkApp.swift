// © Pexilim
import SwiftUI

@main
struct BlinkApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: scenePhase, initial: true) { _, phase in model.scenePhaseChanged(phase) }
                .task { await model.load() }
        }
        #if os(macOS)
        .defaultSize(width: 480, height: 640)
        #endif
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The lock replaces the content rather than covering it, so nothing renders behind it.
        if model.locked {
            LockView()
        } else {
            NavigationStack {
                switch model.screen {
                case .loading: ProgressView()
                case .connect: ConnectView()
                case .signIn: SignInView()
                case .home: HomeView()
                }
            }
        }
    }
}
