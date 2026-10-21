// © Pexilim
import BlinkKit
import SwiftUI

/// Settings › Connections: every service Blink can use, added right here. Keys and passwords go to the owner's own
/// server (Vault) and can't be read back; ones set as Supabase secrets keep working underneath.
struct ConnectionsSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: [String: String]?
    @State private var saved: Set<String> = []
    @State private var checking = false
    @State private var failed = false
    @State private var editing: Service?
    @State private var removing: Service?
    @State private var problem: String?
    @State private var disconnecting = false
    @State private var connecting: Task<Void, Never>?
    @State private var advanced = false
    @State private var connectingApp: ConnectorApp?

    struct Field: Hashable {
        let key: String, label: String, prompt: String
        var secure = true
        var optional = false
    }

    struct Service: Identifiable, Hashable {
        let id: String           // the status key from the server's check
        let name: String, use: String
        let fields: [Field]
        let getKey: URL?
        let help: String
    }

    /// Advanced: AI services by API key (the simple way is ChatGPT or Claude above, or the free on-device model).
    private let aiKeys: [Service] = [
            Service(id: "anthropic", name: "Claude (Anthropic)", use: "Chat, planning and drafts when Claude is picked",
                    fields: [Field(key: "ANTHROPIC_API_KEY", label: "API key", prompt: "sk-ant-…"),
                             Field(key: "ANTHROPIC_WORKSPACE_ID", label: "Workspace ID", prompt: "Only for organisation keys", secure: false, optional: true)],
                    getKey: URL(string: "https://console.anthropic.com/settings/keys"), help: "Create a key in the Anthropic Console."),
            Service(id: "groq", name: "Groq", use: "Free models and quick text edits",
                    fields: [Field(key: "GROQ_API_KEY", label: "API key", prompt: "gsk_…")],
                    getKey: URL(string: "https://console.groq.com/keys"), help: "Free. Sign in to Groq and create a key."),
            Service(id: "openrouter", name: "OpenRouter", use: "GPT, Gemini, Kimi and DeepSeek through one key",
                    fields: [Field(key: "OPENROUTER_API_KEY", label: "API key", prompt: "sk-or-…")],
                    getKey: URL(string: "https://openrouter.ai/keys"), help: "Add a little credit, then create a key."),
            Service(id: "custom", name: "Your own AI", use: "Any OpenAI-compatible service: Mistral, Together, Perplexity, DeepInfra…",
                    fields: [Field(key: "CUSTOM_AI_NAME", label: "Name", prompt: "e.g. Mistral", secure: false),
                             Field(key: "CUSTOM_AI_URL", label: "API address", prompt: "https://api.mistral.ai/v1", secure: false),
                             Field(key: "CUSTOM_AI_MODEL", label: "Model", prompt: "e.g. mistral-large-latest", secure: false),
                             Field(key: "CUSTOM_AI_KEY", label: "API key", prompt: "From that service's dashboard")],
                    getKey: nil, help: "The service's docs list its OpenAI-compatible API address (https, usually ending in /v1) and model names. Then pick “Your own AI” as the model in Settings › AI."),
    ]

    private let otherKeys: [Service] = [
            Service(id: "cloudflare", name: "Cloudflare Workers AI", use: "Free post images",
                    fields: [Field(key: "CLOUDFLARE_ACCOUNT_ID", label: "Account ID", prompt: "On your Cloudflare dashboard's right side", secure: false),
                             Field(key: "CLOUDFLARE_API_TOKEN", label: "API token", prompt: "With the Workers AI permission")],
                    getKey: URL(string: "https://dash.cloudflare.com/profile/api-tokens"), help: "Create a token with the “Workers AI” template."),
            Service(id: "apify", name: "Apify", use: "Read My Page on the Content page",
                    fields: [Field(key: "APIFY_TOKEN", label: "API token", prompt: "apify_api_…")],
                    getKey: URL(string: "https://console.apify.com/settings/integrations"), help: "Copy your personal API token."),
    ]

    private let mail: [Service] = [
            Service(id: "gmail", name: "Gmail", use: "Sorts your mail; replies after Touch ID",
                    fields: [Field(key: "GMAIL_ADDRESS", label: "Address", prompt: "you@gmail.com", secure: false),
                             Field(key: "GMAIL_APP_PASSWORD", label: "App password", prompt: "16 letters from Google")],
                    getKey: URL(string: "https://myaccount.google.com/apppasswords"),
                    help: "Turn on 2-Step Verification, then create an app password named “Blink”."),
            Service(id: "icloud", name: "iCloud Mail", use: "Sorts your mail; replies after Touch ID",
                    fields: [Field(key: "ICLOUD_ADDRESS", label: "Address", prompt: "you@icloud.com", secure: false),
                             Field(key: "ICLOUD_APP_PASSWORD", label: "App-specific password", prompt: "xxxx-xxxx-xxxx-xxxx")],
                    getKey: URL(string: "https://account.apple.com"),
                    help: "Apple Account › Sign-In and Security › App-Specific Passwords."),
            Service(id: "uni", name: "Another mailbox", use: "A work or university account over IMAP",
                    fields: [Field(key: "UNI_ADDRESS", label: "Address", prompt: "you@uni.edu", secure: false),
                             Field(key: "UNI_PASSWORD", label: "Password", prompt: "Your mail password or app password"),
                             Field(key: "UNI_IMAP_HOST", label: "IMAP server", prompt: "imap.example.edu", secure: false),
                             Field(key: "UNI_SMTP_HOST", label: "SMTP server", prompt: "Leave empty if it's the same", secure: false, optional: true)],
                    getKey: nil, help: "Your provider's help page lists the IMAP and SMTP server names."),
    ]

    private let googleApp = Service(
        id: "google_app", name: "Your Google app", use: "Needed once before Connect Google",
        fields: [Field(key: "GOOGLE_CLIENT_ID", label: "Client ID", prompt: "….apps.googleusercontent.com", secure: false),
                 Field(key: "GOOGLE_CLIENT_SECRET", label: "Client secret", prompt: "GOCSPX-…")],
        getKey: URL(string: "https://console.cloud.google.com/auth/clients"),
        help: "A Web application client whose redirect URI is your server's /functions/v1/google/callback.")

    var body: some View {
        Form {
            Section {
                #if os(macOS)
                connectRow(.chatGPT, about: "Use Blink inside ChatGPT, with your ChatGPT plan")
                connectRow(.claude, about: "Use Blink inside Claude, with your Claude plan")
                #endif
                LabeledContent {
                    let problem = OnDeviceChat.problem
                    Label(problem == nil ? "Working" : "Off", systemImage: problem == nil ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(problem == nil ? Color.green : .secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On this Mac")
                        Text(OnDeviceChat.problem ?? "Free, private answers in the notch (Apple Intelligence)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("AI brain")
            } footer: {
                Text("The notch answers on this Mac for free. Connect ChatGPT or Claude to use Blink from there with the plan you already pay for. API keys are under Advanced.")
            }
            Section("Mail") {
                ForEach(mail) { row($0) }
            }
            Section {
                LabeledContent {
                    if let account = model.googleAccount {
                        HStack {
                            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green).help(account)
                            Button("Disconnect…", role: .destructive) { disconnecting = true }
                        }
                    } else if let connecting {
                        HStack {
                            ProgressView().controlSize(.small).accessibilityLabel("Connecting Google")
                            Text("Finish in your browser…").foregroundStyle(.secondary)
                            Button("Cancel") { connecting.cancel() }
                        }
                    } else {
                        Button("Connect Google…") { connectGoogle() }
                            .disabled(!oneClick && status?["google_app"] != "ok")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Calendar")
                        Text(model.googleAccount.map { "\($0) · /meet creates Meet invites" } ?? "For /meet: Meet links and invites from the notch")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                // Without Blink's built-in Google client, the owner's own Google app is the only way, so it shows up front.
                if !oneClick { row(googleApp) }
            } header: {
                Text("Calendar")
            } footer: {
                Text("Blink only creates the meetings you approve with Touch ID. The access stays on your server.")
            }
            Section {
                DisclosureGroup("Advanced: API keys and links", isExpanded: $advanced) {
                    ForEach(aiKeys) { row($0) }
                    if let credit = status?["openrouter_credit"], !credit.isEmpty {
                        LabeledContent("OpenRouter credit left", value: "$\(credit)")
                    }
                    ForEach(otherKeys) { row($0) }
                    if oneClick { row(googleApp) }
                    #if os(macOS)
                    ConnectorLinks()
                    #endif
                }
                HStack {
                    Button("Check Again") { Task { await check() } }.disabled(checking)
                    if checking { ProgressView().controlSize(.small) }
                    if failed { Text("Couldn't reach your server.").foregroundStyle(.orange) }
                    if let problem { Text(problem).foregroundStyle(.orange) }
                }
            } footer: {
                Text("Keys are stored encrypted on your own server and can't be read back, only replaced or removed. Each check is free and read-only.")
            }
        }
        .formStyle(.grouped)
        .task { await check() }
        .task { await model.loadGoogle() }
        // Back from Google's page in the browser: show the new connection. (On the Mac, scenePhase stays active.)
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.loadGoogle() }
        }
        #else
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.loadGoogle() } } }
        #endif
        #if os(macOS)
        .sheet(item: $connectingApp) { app in ConnectorSheet(app: app) { connectingApp = nil } }
        #endif
        .sheet(item: $editing) { service in
            KeySheet(service: service, done: { editing = nil; Task { await check() } })
        }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) { if let removing { Task { await remove(removing) } } }
        } message: {
            Text("Blink stops using it. A key set as a Supabase secret, if there is one, applies again.")
        }
        .confirmationDialog("Disconnect Google?", isPresented: $disconnecting) {
            Button("Disconnect", role: .destructive) { Task { problem = await model.disconnectGoogle() } }
        } message: {
            Text("Blink's access is revoked at Google and deleted from your server. /meet stops working until you connect again.")
        }
    }

    #if os(macOS)
    private func connectRow(_ app: ConnectorApp, about: String) -> some View {
        LabeledContent {
            Button("Connect…") { connectingApp = app }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.rawValue)
                Text(about).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    #endif

    private func row(_ service: Service) -> some View {
        let state = status?[service.id]
        let inApp = service.fields.contains { saved.contains($0.key) }
        return LabeledContent {
            HStack(spacing: 10) {
                Label(word(state), systemImage: symbol(state)).foregroundStyle(tint(state)).labelStyle(.titleAndIcon)
                Button(state == "ok" || inApp ? "Change…" : "Add…") { editing = service }
                if inApp {
                    Button("Remove", role: .destructive) { removing = service }
                        .accessibilityLabel("Remove \(service.name)")
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                Text(service.use + (state == "ok" && !inApp ? " · set on your server" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func check() async {
        guard let server = model.server else { return }
        checking = true
        defer { checking = false }
        do {
            async let checked = server.connections()
            async let names = server.savedKeys()
            let (s, n) = try await (checked, names)
            status = s
            saved = n
            model.updateKeyStatus(s)
            failed = false
        } catch { failed = true }
    }

    private func remove(_ service: Service) async {
        guard let server = model.server else { return }
        do {
            for field in service.fields where saved.contains(field.key) { try await server.removeKey(field.key) }
            problem = nil
        } catch { problem = "Couldn't remove it. Try again." }
        removing = nil
        await check()
    }

    /// Blink's built-in Google client (one click), else the owner's own Google app.
    private var oneClick: Bool {
        #if os(macOS)
        GoogleSignIn.client != nil
        #else
        false
        #endif
    }

    private func connectGoogle() {
        #if os(macOS)
        if oneClick {
            connecting = Task {
                problem = await model.connectGoogleOneClick()
                connecting = nil
            }
            return
        }
        #endif
        Task {
            let (url, failure) = await model.googleConnectURL()
            problem = failure
            if let url { openURL(url) }
        }
    }

    private func word(_ s: String?) -> String {
        switch s {
        case "ok": "Working"
        case "missing": "Not added"
        case "rejected": "Key rejected"
        case "unreachable": "Can't reach"
        default: "Checking…"
        }
    }

    private func symbol(_ s: String?) -> String {
        switch s {
        case "ok": "checkmark.circle.fill"
        case "missing": "minus.circle"
        case "rejected": "xmark.octagon.fill"
        case "unreachable": "wifi.exclamationmark"
        default: "ellipsis.circle"
        }
    }

    private func tint(_ s: String?) -> Color {
        switch s {
        case "ok": .green
        case "rejected": .red
        case "missing", "unreachable": .orange
        default: .secondary
        }
    }
}

/// Adds or replaces one service's key(s). Empty optional fields are left as they are.
private struct KeySheet: View {
    @Environment(AppModel.self) private var model
    let service: ConnectionsSettings.Service
    let done: () -> Void
    @State private var values: [String: String] = [:]
    @State private var saving = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(service.name).font(.title2.weight(.semibold))
            Text(service.use).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(service.help).font(.callout)
                if let url = service.getKey { Link("Get it…", destination: url) }
            }
            Form {
                ForEach(service.fields, id: \.key) { field in
                    let binding = Binding(get: { values[field.key, default: ""] }, set: { values[field.key] = $0 })
                    if field.secure {
                        SecureField(field.label, text: binding, prompt: Text(field.prompt))
                    } else {
                        TextField(field.label, text: binding, prompt: Text(field.prompt))
                    }
                }
            }
            .formStyle(.grouped)
            if let problem { Text(problem).foregroundStyle(.orange).font(.callout) }
            HStack {
                Text("Saved encrypted on your server. It can't be shown again.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel, action: done).keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || !ready)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onChange(of: problem) { if let problem { AccessibilityNotification.Announcement(problem).post() } }
    }

    private var ready: Bool {
        service.fields.allSatisfy { $0.optional || !(values[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func save() async {
        guard let server = model.server else { problem = "Connect to your server first."; return }
        saving = true
        defer { saving = false }
        do {
            for field in service.fields {
                let value = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { try await server.saveKey(field.key, value: value) }
            }
            done()
        } catch {
            problem = "Couldn't save. Check your connection and try again."
        }
    }
}
