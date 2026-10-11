// © Pexilim
import BlinkKit
import SwiftUI

/// Phase 0 placeholder: who and where you're connected, last sync, sign out.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let host = model.server?.config.host ?? "your server"
        Form {
            Section {
                switch model.status {
                case .checking:
                    Label("Checking \(host)…", systemImage: "arrow.triangle.2.circlepath")
                case .connected:
                    Label("Connected to \(host) as \(model.email ?? "you")", systemImage: "checkmark.circle")
                case .unreachable:
                    Label("Can't reach \(host) right now. Blink will try again when you open it.",
                          systemImage: "wifi.exclamationmark")
                    Button("Try again") { Task { await model.refresh() } }
                }
                if let lastSync = model.lastSync {
                    LabeledContent("Last sync") { Text(lastSync, format: .relative(presentation: .named)) }
                } else {
                    LabeledContent("Last sync", value: "Not yet")
                }
            }
            Section {
                NavigationLink("Blink's eyes") { EyesPreview() }
            }
            Section {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Blink")
        .task { await model.refresh() }
    }
}
