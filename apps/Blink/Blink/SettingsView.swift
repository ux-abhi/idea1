// © Pexilim
#if os(macOS)
import BlinkKit
import LocalAuthentication
import SwiftUI

/// Settings (⌘,), behind the same app lock as the window. Sections follow ARCHITECTURE §36.2;
/// Models & cost, Connections, Automatic rules and Data arrive with the features they control.
struct SettingsRoot: View {
    /// The tabs, by key, so a prompt elsewhere ("Add a key") can open the right one.
    enum Section: String { case general, shortcuts, usage, connections, privacy, server, devices }

    @Environment(AppModel.self) private var model
    @AppStorage("settings.tab") private var tab: Section = .general

    var body: some View {
        Group {
            if model.locked {
                LockView()
            } else if model.screen == .home {
                TabView(selection: $tab) {
                    Tab("General", systemImage: "gearshape", value: .general) {
                        Form {
                            DaySettings()
                            NotchSettings()
                            CalendarSettings()
                        }
                        .formStyle(.grouped)
                    }
                    Tab("Shortcuts", systemImage: "command", value: .shortcuts) { ShortcutSettings() }
                    Tab("AI", systemImage: "sparkles", value: .usage) { UsageSettings() }
                    Tab("Connections", systemImage: "key", value: .connections) { ConnectionsSettings() }
                    Tab("Privacy", systemImage: "lock.shield", value: .privacy) { PrivacySettings() }
                    Tab("Server", systemImage: "server.rack", value: .server) { ServerSettings() }
                    Tab("Devices", systemImage: "laptopcomputer.and.iphone", value: .devices) { DevicesSettings() }
                }
            } else {
                ContentUnavailableView("Connect your server first", systemImage: "server.rack",
                                       description: Text("Settings appear once Blink is connected to your server and you're signed in."))
            }
        }
        .frame(width: 680, height: 560)
    }
}

/// How the notch looks when nothing is happening (§36.2).
enum RestStyle: String, CaseIterable, Identifiable {
    case ears, menuBar, hidden
    var id: Self { self }
    static let key = "restStyle"

    var title: String {
        switch self {
        case .ears: "Show Blink's eyes in the notch"
        case .menuBar: "Hide the eyes, keep the menu bar icon"
        case .hidden: "Hide everything until something happens"
        }
    }

    static var current: RestStyle { RestStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .ears }
}

struct ServerSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmSwitch = false
    @State private var confirmRestart = false
    @State private var shownPassword: String?
    @State private var loginProblem: String?

    var body: some View {
        Form {
            if let ref = model.pausedProject {
                Section {
                    Label("Your free server is asleep. Supabase pauses free servers after a week without use; your data is safe.",
                          systemImage: "moon.zzz")
                    Button("Wake It Up…") { openURL(URL(string: "https://supabase.com/dashboard/project/\(ref)")!) }
                } footer: {
                    Text("On the page that opens, click Restore. It takes a minute or two, then Blink connects again.")
                }
            }
            LabeledContent("Server", value: model.server?.config.host ?? "–")
            LabeledContent("Signed in as", value: model.email ?? "–")
            LabeledContent("Last sync") {
                if let lastSync = model.lastSync {
                    Text(lastSync, format: .relative(presentation: .named))
                } else {
                    Text("Not yet")
                }
            }
            // The login Blink made during setup: needed only to sign in on another Mac or after a reinstall.
            // Only when it's the login of this server (a different server signed in by hand has its own).
            if let login = model.savedLogin, model.email == nil || model.email == login.email {
                Section {
                    LabeledContent("Email") { Text(login.email).textSelection(.enabled) }
                    LabeledContent("Password") {
                        if let shownPassword {
                            #if os(macOS)
                            // Concealed, so it never lands in Blink's own clipboard history.
                            CopyRow(label: "", value: shownPassword, secret: true)
                            #else
                            Text(shownPassword).font(.body.monospaced()).textSelection(.enabled)
                            #endif
                        } else {
                            Button("Show…") { Task { await reveal(login.password) } }
                        }
                    }
                    if let loginProblem { Text(loginProblem).foregroundStyle(.orange) }
                } header: {
                    Text("Your Blink login")
                } footer: {
                    Text("Blink made this when it set up your server. Save it in Passwords to sign in on another Mac. Lost it? Reset it in Supabase › Authentication › Users.")
                }
            }
            Section {
                Button("Sign Out") { Task { await model.signOut() } }
            }
            Section {
                LabeledContent("Blink on your server") {
                    Text(model.serverBehind ? "An update is ready" : "Up to date").foregroundStyle(model.serverBehind ? .orange : .secondary)
                }
                if model.serverBehind { UpdateServerButton() }
            } footer: {
                Text("After Blink updates, your server may need its matching update. Blink asks you to sign in with Supabase each time and never keeps that sign-in.")
            }
            Section("Advanced") {
                Button("Use a Different Server…") { confirmSwitch = true }
                Button("Restart Setup…") { confirmRestart = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Sign out and run setup again?", isPresented: $confirmRestart) {
            Button("Sign Out and Restart Setup", role: .destructive) { Task { await model.restartSetup() } }
        } message: {
            Text("You'll see the welcome steps again. Your data stays on \(model.server?.config.host ?? "your server"); pick \"I already have a server\" to reconnect.")
        }
        .confirmationDialog("Use a different server?", isPresented: $confirmSwitch) {
            Button("Sign Out and Switch", role: .destructive) {
                Task {
                    await model.signOut()
                    await model.useDifferentServer()
                }
            }
        } message: {
            Text("You'll be signed out here. Your data stays on \(model.server?.config.host ?? "this server").")
        }
    }

    /// Shows the password only after Touch ID (or the Mac's password).
    private func reveal(_ password: String) async {
        let context = LAContext()
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "show your Blink login")
            shownPassword = password
            loginProblem = nil
        } catch {
            loginProblem = (error as? LAError)?.code == .userCancel ? nil : "Couldn't confirm it's you."
        }
    }
}

struct DevicesSettings: View {
    @Environment(AppModel.self) private var model
    @State private var devices: [BlinkServer.DeviceInfo] = []
    @State private var revoking: BlinkServer.DeviceInfo?
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                ForEach(devices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: device.platform == "macos" ? "laptopcomputer" : "iphone")
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(device.name)
                                if isThisDevice(device) { Text("This Mac").font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(detail(device)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if device.revokedAt == nil && !isThisDevice(device) {
                            Button("Revoke…") { revoking = device }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text("Only the device marked \"Approves red actions\" can confirm sending email, posting or money. Adding another device for that comes with pairing.")
            }
            if let problem { Text(problem).foregroundStyle(.orange) }
        }
        .formStyle(.grouped)
        .task { await load() }
        .confirmationDialog("Revoke \(revoking?.name ?? "this device")?", isPresented: Binding(
            get: { revoking != nil }, set: { if !$0 { revoking = nil } })) {
            Button("Revoke", role: .destructive) {
                guard let device = revoking else { return }
                Task {
                    do {
                        try await model.server?.revoke(deviceID: device.id)
                        await load()
                    } catch {
                        problem = "Couldn't revoke. Check your connection and try again."
                    }
                }
            }
        } message: {
            Text(revoking?.hasApprovalKey == true
                 ? "It can no longer approve red actions, and none of your devices can until a new one is paired."
                 : "It stays signed out of your server.")
        }
    }

    private func load() async {
        guard let list = try? await model.server?.devices() else { return }
        devices = list
    }

    private func isThisDevice(_ device: BlinkServer.DeviceInfo) -> Bool {
        device.id.lowercased() == model.server?.currentDeviceID
    }

    private func detail(_ device: BlinkServer.DeviceInfo) -> String {
        if device.revokedAt != nil { return "Revoked" }
        var parts: [String] = []
        if device.hasApprovalKey { parts.append("Approves red actions") }
        if let seen = device.lastSeenAt { parts.append("Seen \(seen.formatted(.relative(presentation: .named)))") }
        return parts.isEmpty ? "Never checked in" : parts.joined(separator: " · ")
    }
}

/// Calendar access, as sections of the General tab.
struct CalendarSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            switch model.calendarAccess {
            case .granted:
                LabeledContent("Access", value: "Calendars and reminders")
                LabeledContent("Next 14 days", value: "\(model.calendarEvents.count) meetings")
                LabeledContent("Due today", value: "\(model.agenda.reminders.count) reminders")
            case .notAsked:
                Button("Connect Calendar") { Task { await model.connectCalendar() } }
            case .denied:
                Text("Calendar access is off.")
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("All-day events and ones you've declined are left out. The next 14 days are copied to your server for your other devices.")
        }
    }
}

struct NotchSettings: View {
    @AppStorage(RestStyle.key) private var restStyle = RestStyle.ears
    @AppStorage(AppModel.finishSoundKey) private var finishSound = true
    @AppStorage(MeetingRecorder.languageKey) private var notesLanguage = Locale.current.identifier(.bcp47)
    @State private var mood = Mood.idle
    @State private var openAtLogin = false
    @State private var loginProblem: String?

    var body: some View {
        Group {
            Section {
                Picker("When nothing is happening", selection: $restStyle) {
                    ForEach(RestStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Notch")
            } footer: {
                Text("Meetings and things that need you still appear in the notch.")
            }
            Section("Sound") {
                Toggle("Play a soft sound when you finish something", isOn: $finishSound)
            }
            Section {
                Picker("Meetings are in", selection: $notesLanguage) {
                    ForEach(MeetingRecorder.languages, id: \.id) { Text($0.name).tag($0.id) }
                    // The Mac's own language, when it isn't one of these.
                    if !MeetingRecorder.languages.contains(where: { $0.id == notesLanguage }) {
                        Text(Locale.current.localizedString(forIdentifier: notesLanguage) ?? notesLanguage).tag(notesLanguage)
                    }
                }
            } header: {
                Text("Meeting Notes")
            } footer: {
                Text("Say or type “take notes” in the notch, or click Take Notes on a meeting. Speech becomes text on this Mac and the sound is never kept; the summary is written on this Mac too. Tell everyone on the call that you're taking notes.")
            }
            Section("Startup") {
                Toggle("Open Blink when you log in", isOn: Binding(get: { openAtLogin }, set: { on in
                    loginProblem = LoginItem.set(on)
                    openAtLogin = LoginItem.isOn
                }))
                if let loginProblem { Text(loginProblem).font(.caption).foregroundStyle(.orange) }
                Text("Your morning brief then shows on the first unlock of the day.").font(.caption).foregroundStyle(.secondary)
            }
            .onAppear { openAtLogin = LoginItem.isOn }
            Section("Blink's eyes") {
                // The notch's own size: the eyes scale with their frame, so a wide box makes them huge.
                BlinkEyes(mood: mood)
                    .frame(width: 200, height: 64)
                    .padding(.vertical, 23)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .background(.black, in: .rect(cornerRadius: Tokens.Radius.tile, style: .continuous))
                Picker("Mood", selection: $mood) {
                    ForEach(Mood.allCases) { Text($0.word).tag($0) }
                }
            }
        }
    }
}

/// Light, dark or like the Mac; the notch stays dark either way.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    static let key = "appearance"

    var title: String {
        switch self {
        case .system: "Match the Mac"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Appearance, wake and evening times, and the keyboard shortcuts.
struct DaySettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Appearance.key) private var appearance = Appearance.system

    var body: some View {
        Group {
            Section {
                AssistantNameField()
            } footer: {
                Text("What you call your assistant. It answers to this name in chat and voice commands (“Hey \(AssistantName.current), open Figma”) and uses it for itself.")
            }
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                // Here too, so it applies even when only Settings is open.
                .onChange(of: appearance) { NSApp.appearance = appearance.nsAppearance }
            }
            Section {
                DatePicker("Wake up", selection: binding(\.wake), displayedComponents: .hourAndMinute)
                DatePicker("Evening check-in", selection: binding(\.evening), displayedComponents: .hourAndMinute)
            } footer: {
                Text("Your habit day ends when you wake up, so a late night still counts for the day before. The evening check-in opens in the notch at the second time.")
            }
            Section {
                @Bindable var model = model
                Toggle("I post on social media", isOn: $model.showsContent)
            } footer: {
                Text("Shows Content: post ideas and drafts in your voice, and how your posts do.")
            }
            if let problem = model.saveProblem {
                Text(problem).foregroundStyle(.orange)
            }
        }
    }

    /// A time on today's date for the picker; saving keeps only hour and minute.
    private func binding(_ key: KeyPath<AppModel, (hour: Int, minute: Int)>) -> Binding<Date> {
        Binding(
            get: {
                let t = model[keyPath: key]
                return Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: .now) ?? .now
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let t = (hour: c.hour ?? 0, minute: c.minute ?? 0)
                let isWake = key == \AppModel.wake
                Task { await model.setDayTimes(wake: isWake ? t : model.wake, evening: isWake ? model.evening : t) }
            })
    }
}

/// Which AI does what, and what it cost this month (the server logs every Claude and Groq request).
struct UsageSettings: View {
    @Environment(AppModel.self) private var model
    @State private var month: [BlinkServer.Usage]?
    @State private var day: Double?
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Chat and planning") { ModelMenu(feature: "chat") }
                LabeledContent("Content drafts") { ModelMenu(feature: "content") }
                LabeledContent("Voice commands and dictation") { ModelMenu(feature: "voice") }
                LabeledContent("Quick text edits", value: "GPT-OSS 20B on Groq")
                Picker("Daily limit for paid models", selection: Binding(
                    get: { model.aiCaps.day ?? 0 },
                    set: { cap in var caps = model.aiCaps; caps.day = cap > 0 ? cap : nil; Task { await model.setAICaps(caps) } })) {
                    Text("Default ($1)").tag(0.0)
                    ForEach([0.5, 1, 2, 5, 10, 20], id: \.self) { Text($0.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))).tag($0) }
                }
                .disabled(!model.capsLoaded)
                Picker("Monthly limit for paid models", selection: Binding(
                    get: { model.aiCaps.month ?? 0 },
                    set: { cap in var caps = model.aiCaps; caps.month = cap > 0 ? cap : nil; Task { await model.setAICaps(caps) } })) {
                    Text("Default ($10)").tag(0.0)
                    ForEach([5.0, 10, 20, 30, 50, 100], id: \.self) { Text($0.formatted(.currency(code: "USD").precision(.fractionLength(0)))).tag($0) }
                }
                .disabled(!model.capsLoaded)
                if let day {
                    LabeledContent("Paid models, last 24 hours", value: day.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                        .foregroundStyle(day >= (model.aiCaps.day ?? 1) ? .orange : .secondary)
                }
                if let problem = model.modelProblem { Text(problem).foregroundStyle(.orange) }
            } header: {
                Text("Models")
            } footer: {
                Text("Groq models use your Groq key and its free daily limits. Claude is stronger at following Blink's safety rules; with any model, nothing changes until you approve the card. Without a choice, free Groq writes everything and paid models stop at $1 a day and $10 a month. Past a limit, Claude and OpenRouter pause until the spend of the last 24 hours (or 30 days) drops; free models keep working.")
            }
            Section {
                if let month {
                    let total = month.reduce(0) { $0 + $1.costUSD }
                    LabeledContent("Spent so far", value: total.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                    LabeledContent("Requests", value: "\(month.count)")
                    ForEach(Set(month.map(\.model)).sorted(), id: \.self) { name in
                        LabeledContent(name, value: month.filter { $0.model == name }.reduce(0) { $0 + $1.costUSD }
                            .formatted(.currency(code: "USD").precision(.fractionLength(2))))
                            .foregroundStyle(.secondary)
                    }
                } else if failed {
                    Text("Couldn't load usage from your server.").foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            } header: {
                Text("This month")
            } footer: {
                Text("Estimated from list prices; Groq's free tier may cost nothing. Your Anthropic and Groq consoles show the exact bill.")
            }
        }
        .formStyle(.grouped)
        .task {
            await model.loadModelPrefs()
            guard let server = model.server else { return }
            let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
            do { month = try await server.usage(since: start) } catch { failed = true }
            day = (try? await server.usage(since: .now.addingTimeInterval(-86_400)))?
                .filter { usage in AIModel.all.contains { $0.id == usage.model && !$0.isFree } }.reduce(0) { $0 + $1.costUSD }
        }
    }
}

struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    @State private var clearingChat = false
    @State private var clearingClipboard = false
    @AppStorage("lockAfter") private var lockAfter = AppLock.defaultRelockAfter
    @AppStorage(ClipboardStore.pausedKey) private var clipboardPaused = false
    @Environment(ClipboardStore.self) private var clipboard

    var body: some View {
        Form {
            Section {
                Picker("Lock Blink after", selection: $lockAfter) {
                    Text("1 minute away").tag(60.0)
                    Text("5 minutes away").tag(300.0)
                    Text("15 minutes away").tag(900.0)
                    Text("1 hour away").tag(3600.0)
                }
                @Bindable var model = model
                Toggle("Show the notch in screenshots and recordings", isOn: $model.notchInRecordings)
            } footer: {
                Text("Leave recordings off to keep your mail, money and tasks out of screen sharing.")
            }
            Section {
                Toggle("Keep clipboard history (⌃⌥V)", isOn: Binding(get: { !clipboardPaused }, set: { clipboardPaused = !$0 }))
                Button("Clear Clipboard History (\(clipboard.history.items.count))…", role: .destructive) { clearingClipboard = true }
                    .disabled(clipboard.history.items.isEmpty)
                    .confirmationDialog("Clear your clipboard history?", isPresented: $clearingClipboard) {
                        Button("Clear History", role: .destructive) { clipboard.clear() }
                    } message: {
                        Text("Everything you copied is removed from Blink. This can't be undone.")
                    }
                Button("Clear Chat History…", role: .destructive) { clearingChat = true }
                    .disabled(model.chat.isEmpty)
                    .confirmationDialog("Clear your chat with Blink?", isPresented: $clearingChat) {
                        Button("Clear Chat History", role: .destructive) { model.clearChat() }
                    } message: {
                        Text("This removes the conversation from this Mac. Cards waiting for your OK, your notes and tasks stay.")
                    }
            } header: {
                Text("History")
            } footer: {
                Text("The last 50 things you copy and your last 20 chat messages, kept on this Mac only. Passwords from password managers are never kept.")
            }
            Section {
                if let problem = model.rulesProblem {
                    Text(problem).foregroundStyle(.red)
                } else if model.senderRules.isEmpty {
                    Text("Nothing yet. When you mark a sender Always or Never Important in Mail, Blink remembers it here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.senderRules) { rule in
                    LabeledContent {
                        Button("Forget") { Task { await model.forget(rule) } }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.sender)
                            Text((rule.important ? "Always important" : "Never important") + (rule.example.flatMap { $0.isEmpty ? nil : " · e.g. “\($0)”" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } header: {
                Text("What Blink has learned")
            } footer: {
                Text("Forget a rule and later mail from that sender is sorted on its own again.")
            }
            .task { await model.loadSenderRules() }
            Section {
                DisclosureGroup("What leaves this Mac") {
                    Label("Your next 14 days of meetings: title, time, place and link", systemImage: "calendar")
                    Label("This Mac's name and your time zone", systemImage: "laptopcomputer")
                    Label("Your decisions on cards, and a signature for red ones", systemImage: "checkmark.seal")
                    Label("When you ask Blink: your question with your calendar, tasks, notes, habits and open reminders, sent to the AI through your server",
                          systemImage: "bubble.left")
                    Label("Never: your fingerprint. Touch ID only unlocks a key that stays in the Secure Enclave", systemImage: "touchid")
                }
            } footer: {
                Text("Everything goes only to your own server, never to Pexilim.")
            }
        }
        .formStyle(.grouped)
    }
}
#endif

/// Settings › General › Name: saved on Return or when the field loses focus; a name that can't be used says why.
struct AssistantNameField: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AssistantName.key) private var saved = AssistantName.standard
    @State private var typed = ""
    @State private var problem: String?

    var body: some View {
        LabeledContent("Name") {
            HStack {
                if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
                TextField("Name", text: $typed, prompt: Text(AssistantName.standard))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 180)
                    .onSubmit(save)
                    .disabled(!model.capsLoaded)
            }
        }
        .onAppear { typed = AssistantName.current }
        .onDisappear(perform: save)
    }

    private func save() {
        let wanted = typed.trimmingCharacters(in: .whitespaces).isEmpty ? AssistantName.standard : typed
        guard let name = AssistantName.checked(wanted) else {
            problem = "Letters, numbers and spaces, up to 24"
            return
        }
        problem = nil
        typed = name
        guard name != AssistantName.current else { return }
        Task { await model.setAssistantName(name) }
    }
}
