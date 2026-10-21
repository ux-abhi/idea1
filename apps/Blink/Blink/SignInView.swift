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
                    if working { ProgressView().controlSize(.small) } else { Text("Sign In") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(email.isEmpty || password.isEmpty || working)
                Button("Use a different server") { Task { await model.useDifferentServer() } }
                    .buttonStyle(.borderless).font(.callout)
            }
        }
        .formStyle(.grouped)
        .onChange(of: problem) { if let problem { AccessibilityNotification.Announcement(problem).post() } }
        // This Mac knows the login (Blink made it, or set it): sign straight in, nothing to type. Not right after the
        // owner pressed Sign Out, so they can switch account. A failed try just leaves the form filled in.
        .task {
            // Only to the server this login was made for: never send it to another server that's been connected.
            guard !model.signedOutOnPurpose, !working, let login = model.savedLogin,
                  let host = model.savedLoginHost, host == model.server?.config.host else { return }
            (email, password) = (login.email, login.password)
            working = true
            let failed = await model.signIn(email: login.email, password: login.password) != nil
            working = false
            if !failed { password = "" }
        }
        .navigationTitle("Sign in")
    }

    private func signIn() async {
        working = true
        problem = await model.signIn(email: email, password: password)
        working = false
        if problem == nil { password = "" }
    }
}
