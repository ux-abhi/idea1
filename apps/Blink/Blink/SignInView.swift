// © Pexilim
import BlinkKit
import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var problem: String?
    @State private var working = false

    var body: some View {
        Form {
            if let notice = model.signInNotice {
                Section { Label(notice, systemImage: "person.crop.circle.badge.exclamationmark") }
            }
            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    // The login Blink made when it set up the server: nobody has to remember it.
                    .onAppear {
                        if email.isEmpty, password.isEmpty, let login = model.savedLogin { (email, password) = (login.email, login.password) }
                    }
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } footer: {
                if let host = model.server?.config.host { Text("Server: \(host)") }
            }
            if let problem {
                Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Section {
                Button {
                    Task { await signIn() }
                } label: {
                    if working { ProgressView().controlSize(.small) } else { Text("Sign in") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(email.isEmpty || password.isEmpty || working)
                Button("Use a different server") { Task { await model.useDifferentServer() } }
            }
        }
        .formStyle(.grouped)
        .onChange(of: problem) { if let problem { AccessibilityNotification.Announcement(problem).post() } }
        .navigationTitle("Sign in")
    }

    private func signIn() async {
        working = true
        problem = await model.signIn(email: email, password: password)
        working = false
        if problem == nil { password = "" }
    }
}
