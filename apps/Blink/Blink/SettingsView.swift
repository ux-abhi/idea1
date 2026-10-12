// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Settings (⌘,), behind the same app lock as the window. Sections follow ARCHITECTURE §36.2;
/// Models & cost, Connections, Automatic rules and Data arrive with the features they control.
struct SettingsRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.locked {
                LockView()
            } else if model.screen == .home {
                TabView {
                    Tab("Server", systemImage: "server.rack") { ServerSettings() }
                    Tab("Devices", systemImage: "laptopcomputer.and.iphone") { DevicesSettings() }
                    Tab("Calendar", systemImage: "calendar") { CalendarSettings() }
                    Tab("Your Day", systemImage: "sun.horizon") { DaySettings() }
                    Tab("Blink & Notch", systemImage: "eyes") { NotchSettings() }
                    Tab("AI & Usage", systemImage: "sparkles") { UsageSettings() }
                    Tab("Privacy", systemImage: "lock.shield") { PrivacySettings() }
                }
            } else {
                ContentUnavailableView("Connect your server first", systemImage: "server.rack",
                                       description: Text("Settings appear once Blink is connected to your server and you're signed in."))
            }
        }
        .frame(width: 520, height: 460)
    }
}

/// How the notch looks when nothing is happening (§36.2).
enum RestStyle: String, CaseIterable, Identifiable {
    case ears, menuBar, hidden
    var id: Self { self }
    static let key = "restStyle"

    var title: String {
        switch self {
        case .ears: "Slim ears"
        case .menuBar: "Menu bar icon only"
        case .hidden: "Hidden until something happens"
        }
    }

    static var current: RestStyle { RestStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .ears }
}

struct ServerSettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSwitch = false

    var body: some View {
        Form {
            LabeledContent("Server", value: model.server?.config.host ?? "–")
            LabeledContent("Signed in as", value: model.email ?? "–")
            LabeledContent("Last sync") {
                if let lastSync = model.lastSync {
                    Text(lastSync, format: .relative(presentation: .named))
                } else {
                    Text("Not yet")
                }
            }
            HStack {
                Button("Sign Out") { Task { await model.signOut() } }
                Button("Use a Different Server…") { confirmSwitch = true }
            }
        }
        .formStyle(.grouped)
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

struct CalendarSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            switch model.calendarAccess {
            case .granted:
                LabeledContent("Access", value: "Calendars and reminders")
                LabeledContent("Next 7 days", value: "\(model.agenda.events.count) meetings")
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
            Section {
                Text("Blink reads every calendar on this Mac. All-day events and ones you've declined are left out. The next 7 days are copied to your server so your other devices can use them. Reminders stay on this Mac, except their titles and times go along when you ask Blink something.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct NotchSettings: View {
    @AppStorage(RestStyle.key) private var restStyle = RestStyle.ears
    @State private var mood = Mood.idle

    var body: some View {
        Form {
            Picker("When nothing is happening", selection: $restStyle) {
                ForEach(RestStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Section {
                Text("Meetings and things that need you still appear in the notch, whichever you choose.")
                    .foregroundStyle(.secondary)
            }
            Section("Blink's eyes") {
                BlinkEyes(mood: mood)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .background(.black, in: .rect(cornerRadius: 18, style: .continuous))
                Picker("Mood", selection: $mood) {
                    ForEach(Mood.allCases) { Text($0.word).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Wake and evening times, and the keyboard shortcuts.
struct DaySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                DatePicker("Wake up", selection: binding(\.wake), displayedComponents: .hourAndMinute)
                DatePicker("Evening check-in", selection: binding(\.evening), displayedComponents: .hourAndMinute)
            } footer: {
                Text("Your habit day ends when you wake up, so a late night still counts for the day before. The evening check-in opens in the notch at the second time.")
            }
            Section("Keyboard shortcuts") {
                LabeledContent("Ask Blink", value: "⌃⌥Space")
                LabeledContent("Clipboard history", value: "⌃⌥V")
                LabeledContent("Approve a card", value: "⌘⏎")
                LabeledContent("Undo the last done", value: "⌘Z")
                LabeledContent("Close the notch", value: "Esc")
            }
            if let problem = model.saveProblem {
                Text(problem).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
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
                LabeledContent("Quick text edits", value: "GPT-OSS 20B on Groq")
                Picker("Daily limit for Claude", selection: Binding(
                    get: { model.dailyCap ?? 0 },
                    set: { cap in Task { await model.setDailyCap(cap > 0 ? cap : nil) } })) {
                    Text("No limit").tag(0.0)
                    ForEach([0.5, 1, 2, 5, 10, 20], id: \.self) { Text($0.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))).tag($0) }
                }
                if let day {
                    LabeledContent("Claude, last 24 hours", value: day.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                        .foregroundStyle(model.dailyCap.map { day >= $0 } == true ? .orange : .secondary)
                }
                if let problem = model.modelProblem { Text(problem).foregroundStyle(.orange) }
            } header: {
                Text("Models")
            } footer: {
                Text("Groq models use your Groq key and its free daily limits. Claude is stronger at following Blink's safety rules; with any model, nothing changes until you approve the card. Past the daily limit, Claude pauses until the spend of the last 24 hours drops; free models keep working.")
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
                .filter { $0.model.hasPrefix("claude") }.reduce(0) { $0 + $1.costUSD }
        }
    }
}

struct PrivacySettings: View {
    @AppStorage("lockAfter") private var lockAfter = AppLock.defaultRelockAfter
    @AppStorage(ClipboardStore.pausedKey) private var clipboardPaused = false
    @Environment(ClipboardStore.self) private var clipboard

    var body: some View {
        Form {
            Picker("Lock Blink after", selection: $lockAfter) {
                Text("1 minute away").tag(60.0)
                Text("5 minutes away").tag(300.0)
                Text("15 minutes away").tag(900.0)
                Text("1 hour away").tag(3600.0)
            }
            Section {
                Toggle("Keep clipboard history", isOn: Binding(get: { !clipboardPaused }, set: { clipboardPaused = !$0 }))
                Button("Clear Clipboard History (\(clipboard.history.items.count))", role: .destructive) { clipboard.clear() }
                    .disabled(clipboard.history.items.isEmpty)
            } header: {
                Text("Clipboard (⌃⌥V)")
            } footer: {
                Text("The last 50 things you copy, kept on this Mac only. Passwords copied from password managers are never kept.")
            }
            Section("What leaves this Mac") {
                Label("Your next 7 days of meetings: title, time, place and link", systemImage: "calendar")
                Label("This Mac's name and your time zone", systemImage: "laptopcomputer")
                Label("Your decisions on cards, and a signature for red ones", systemImage: "checkmark.seal")
            }
            Section("Only when you ask Blink") {
                Label("Your open reminders' titles and times go with your question, so Blink can finish or delete one for you", systemImage: "list.bullet")
                Label("Your question, with your calendar, tasks, notes and habits, goes to Claude through your server", systemImage: "bubble.left")
            }
            Section("What stays on this Mac") {
                Label("Your fingerprint. Touch ID only unlocks a key that never leaves the Secure Enclave", systemImage: "touchid")
            }
            Section {
                Text("Everything goes only to your own server, never to Pexilim.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
#endif
