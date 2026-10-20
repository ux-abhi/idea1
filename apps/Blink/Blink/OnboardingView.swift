// © Pexilim
import AuthenticationServices
import BlinkKit
import SwiftUI

/// First run (ARCHITECTURE §36.2 onboarding): Welcome → Server → Account → Calendar → About you. The value moment is
/// the owner's real next meeting, shown in step 4 and in the notch 10 minutes before. Everything else (mail, money,
/// habits, keys) is set up later from Today's setup ring, where it's needed. This view replaces the app's root
/// until it's done, so nothing of the real app renders behind it.
struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, server, account, calendar, about }

    @Environment(AppModel.self) private var model
    @AppStorage("onboarding.welcomed") private var welcomed = false
    @AppStorage("onboarding.done") private var done = false
    @AppStorage("onboarding.calendarSeen") private var calendarSeen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the owner is: the server and sign-in steps follow the app's real state, so a relaunch resumes in place.
    private var step: Step {
        switch model.screen {
        case .loading, .connect: welcomed ? .server : .welcome
        case .signIn: .account
        case .home: calendarSeen ? .about : .calendar
        }
    }

    var body: some View {
        ZStack {
            BlinkCanvasLight()
            if model.screen == .loading {
                ProgressView()
            } else {
                VStack(spacing: 22) {
                    if step != .welcome { StepDots(current: step.rawValue, count: Step.allCases.count - 1) }
                    Group {
                        switch step {
                        case .welcome: WelcomeStep { welcomed = true }
                        case .server: ServerStep()
                        case .account: AccountStep()
                        case .calendar: CalendarStep { calendarSeen = true }
                        case .about: AboutStep { done = true; model.showShortcutTips() }
                        }
                    }
                    .frame(maxWidth: 520)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
                .padding(32)
                .animation(.smooth, value: step)
            }
        }
    }
}

/// The soft canvas, for screens before the main window (the window's own BlinkCanvas is macOS-only).
private struct BlinkCanvasLight: View {
    var body: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.10), Color.clear], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// "Step 2 of 4" as dots.
private struct StepDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...count, id: \.self) { i in
                Capsule().fill(i <= current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(count)")
    }
}

/// One step's frame: a title, a line under it, the content, and the main button.
private struct StepCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(.largeTitle, design: .rounded).weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            content
        }
        .padding(24)
        .background(.background, in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 20, y: 8)
    }
}

// MARK: Steps

private struct WelcomeStep: View {
    let next: () -> Void
    @State private var blink = 0

    var body: some View {
        VStack(spacing: 24) {
            BlinkEyes(mood: .morning, blinkTrigger: blink)
                .frame(width: 180, height: 80)
                .padding(.vertical, 18).padding(.horizontal, 28)
                .background(.black, in: .rect(cornerRadius: 28, style: .continuous))
                .accessibilityHidden(true)
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(3))
                        blink += 1
                    }
                }
            VStack(spacing: 8) {
                Text("Meet Blink").font(.system(size: 40, weight: .semibold, design: .rounded))
                Text("Your assistant in the notch.").font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                point("calendar.badge.clock", "Your day, in the notch", "Meetings, tasks and important mail, right when they matter.")
                point("lock.shield", "Your data stays yours", "Everything lives on your own server. Not even we can read it.")
                point("hand.raised", "It asks before acting", "Nothing is sent, booked or posted without your OK.")
            }
            .padding(20)
            .background(.background, in: .rect(cornerRadius: 20, style: .continuous))
            Button(action: next) {
                Text("Get Started").frame(maxWidth: 260).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            Text("About 3 minutes once your server is ready").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ServerStep: View {
    @State private var manual = ServerInstaller.helper == nil

    var body: some View {
        StepCard(title: "Your own server",
                 subtitle: "Blink keeps everything on your own free Supabase server, so your notes, mail and money stay private. Not even we can read them.") {
            if manual {
                ConnectView()
                    .frame(minHeight: 230, maxHeight: 340)
                DisclosureGroup("Where do I find these?") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This is for a server Blink already set up (on another Mac, say). A new, empty project won't work: use “Create a new server for me” instead.")
                            .foregroundStyle(.secondary)
                        Text("1. Open your Blink project at supabase.com.")
                        Text("2. Project URL: press Connect at the top of the project (or Project Settings › Data API), and copy the URL that ends in .supabase.co.")
                        Text("3. Publishable key: Project Settings › API Keys, the key that starts with sb_publishable_.")
                    }
                    .font(.callout)
                    .padding(.top, 6)
                }
                if ServerInstaller.helper != nil {
                    Button("Create a new server for me instead") { manual = false }.buttonStyle(.borderless)
                }
            } else {
                CreateServer { manual = true }
            }
        }
    }
}

/// One click: sign in with Supabase, and Blink makes the server, sets it up and signs you in.
private struct CreateServer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var installer = ServerInstaller()
    /// The browser sign-in is open; a second click would start a new attempt and void this one.
    @State private var signingIn = false
    let useExisting: () -> Void

    var body: some View {
        if installer.working || installer.step != nil && installer.problem == nil {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ServerInstaller.Step.allCases, id: \.self) { step in
                    let current = installer.step?.rawValue ?? 0
                    HStack(spacing: 10) {
                        if step.rawValue < current {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if step.rawValue == current {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.tertiary)
                        }
                        Text(step.title).foregroundStyle(step.rawValue <= current ? .primary : .secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(step.rawValue < current ? "Done" : step.rawValue == current ? "In progress" : "Waiting")
                }
                Text("Keep Blink open. This takes about 3 minutes.").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Blink creates your own private server and signs you in. No passwords to make up.", systemImage: "server.rack")
                Label("Chat works right away, free and on this Mac. Mail sorting and drafts can use a free key later.", systemImage: "sparkles")
                if let problem = installer.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                Button {
                    Task { await start() }
                } label: {
                    Label(installer.problem == nil ? "Sign in with Supabase" : "Try Again", systemImage: "person.badge.key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(signingIn)
                Text("Opens supabase.com to sign in or sign up for free. Blink then creates your server; we never see your Supabase account.")
                    .font(.caption).foregroundStyle(.secondary)
                // Hidden while setup runs: switching away mid-install would hide its progress, not stop it.
                if !signingIn { Button("I already have a server", action: useExisting).buttonStyle(.borderless) }
            }
        }
    }

    private func start() async {
        guard let url = installer.startURL() else { return }
        signingIn = true
        defer { signingIn = false }
        do {
            let callback = try await webAuth.authenticate(using: url, callbackURLScheme: "blink", preferredBrowserSession: nil)
            let token = try await installer.token(from: callback)
            await installer.install(token: token, model: model)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closing the sign-in window is not a problem worth a message.
        } catch {
            installer.fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

private struct AccountStep: View {
    var body: some View {
        StepCard(title: "Sign in", subtitle: "Use the email and password of your account on this server.") {
            SignInView()
                .frame(minHeight: 230, maxHeight: 340)
            Text("No account yet? Create one in Supabase › Authentication › Users › Add user, then sign in here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The value moment: allow Calendar and see your real next meeting, the way Blink will bring it up in the notch.
private struct CalendarStep: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void
    @State private var asking = false

    var body: some View {
        StepCard(title: "See your day", subtitle: "Blink reads your calendars on this device to bring up each meeting 10 minutes before it starts.") {
            switch model.calendarAccess {
            case .granted:
                if let meeting = model.agenda.events.first(where: { $0.end > .now }) {
                    HStack(spacing: 14) {
                        BlinkEyes(mood: .headsUp).frame(width: 64, height: 28)
                            .padding(10).background(.black, in: .capsule).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meeting.title).font(.headline).lineLimit(1)
                            Text(meeting.start.formatted(.dateTime.weekday(.wide).hour().minute()))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 16))
                    Label("That's your next meeting. Blink will tap you in the notch 10 minutes before it.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                } else {
                    Label("No meetings in the next two weeks. Blink will bring them up as they come.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                }
                Button("Continue", action: next).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            case .denied:
                Label("Calendar access is off. You can turn it on later in Settings › Calendar.", systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Button("Continue", action: next).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            case .notAsked:
                HStack {
                    Button {
                        asking = true
                        Task { await model.connectCalendar(); asking = false }
                    } label: {
                        if asking { ProgressView().controlSize(.small).accessibilityLabel("Asking for Calendar access") } else { Label("Allow Calendar", systemImage: "calendar") }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    Button("Not Now", action: next)
                }
            }
        }
    }
}

/// The few things that make Blink yours from day one; all optional, all changeable later.
private struct AboutStep: View {
    @Environment(AppModel.self) private var model
    let finish: () -> Void
    @State private var handle = ""
    @State private var saving = false
    @State private var openAtLogin = true
    /// Off for a new install; an earlier choice (setup run again) is kept.
    @State private var posts = UserDefaults.standard.object(forKey: "features.content") as? Bool ?? false

    var body: some View {
        StepCard(title: "About you", subtitle: "So Blink shows what you'll use. You can change this later in Settings.") {
            // Content (post ideas, drafts, stats) is for people who post; everyone else never sees it.
            Toggle("I post on social media (Instagram, LinkedIn, X…)", isOn: $posts)
            if posts {
                TextField("Instagram handle, e.g. @yourname (optional)", text: $handle)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { if model.voice.page.contains("@") { handle = String(model.voice.page.split(separator: " ").first ?? "") } }
            }
            if model.aiKeyMissing {
                NeedsSetup(step: model.setupSteps.first { $0.id == .aiKey }!, model: model)
            } else if OnDeviceChat.problem == nil, model.keyStatus?["anthropic"] != "ok" {
                Label("AI is ready: free and private, right on this Mac.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            } else if model.keyStatus != nil {
                Label("Your AI key works. Chat, drafts and sorting are ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            }
            #if os(macOS)
            Toggle("Open Blink when I log in, so my day is ready on the first unlock", isOn: $openAtLogin)
            #endif
            Text("Mail, money accounts and habits come later: Today shows what's left to set up.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Skip") { if openAtLogin { LoginItem.set(true) }; model.showsContent = posts; finish() }
                Button {
                    Task {
                        saving = true
                        let h = handle.trimmingCharacters(in: .whitespaces)
                        // Only once this account loaded (connected): otherwise an empty Voice could replace the saved one.
                        model.showsContent = posts
                        if posts, !h.isEmpty, model.status == .connected, !model.voice.page.contains("@") {
                            var voice = model.voice
                            voice.page = "\(h.hasPrefix("@") ? h : "@" + h) on Instagram"
                            await model.saveVoice(voice)
                        }
                        saving = false
                        if openAtLogin { LoginItem.set(true) }
                        finish()
                    }
                } label: {
                    if saving || model.refreshing { ProgressView().controlSize(.small).accessibilityLabel("Loading") } else { Text("Open Blink") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.refreshing)
            }
        }
        // Load this account first (voice, keys): a returning owner's saved Voice must never be overwritten by an empty one.
        .task {
            await model.refresh()
            if model.voice.page.contains("@"), handle.isEmpty { handle = String(model.voice.page.split(separator: " ").first ?? "") }
        }
    }
}
