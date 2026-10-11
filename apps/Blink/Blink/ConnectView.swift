// © Pexilim
import BlinkKit
import SwiftUI

/// First run: the user's own server address and publishable key.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var key = ""
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                TextField("Project URL", text: $url, prompt: Text("https://your-project.supabase.co"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Publishable key", text: $key, prompt: Text("sb_publishable_…"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } footer: {
                Text("Find both in Supabase › Project Settings › API. Blink keeps them in your Keychain.")
            }
            if let problem {
                Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Section {
                Button("Connect") { Task { await connect() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.isEmpty || key.isEmpty)
            }
        }
        .formStyle(.grouped)
        .onChange(of: problem) { if let problem { AccessibilityNotification.Announcement(problem).post() } }
        .navigationTitle("Connect your server")
    }

    private func connect() async {
        do {
            try await model.connect(url: url, key: key)
        } catch {
            problem = switch error {
            case .invalidURL: "That doesn't look like a web address. Paste the Project URL, starting with https://."
            case .notHTTPS: "Blink only talks to servers over https://."
            case .emptyKey: "Paste the publishable key."
            case .secretKey: "That's the secret key. Use the publishable key; the secret key must never leave your server."
            }
        }
    }
}
