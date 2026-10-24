// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// "Meet Blink": the first-run tour, made like a product film, in its own borderless window. Seven short chapters,
/// each a headline and a live scene on a MacBook screen, with a Try It that opens the real feature. Shown once after
/// setup, and again from Help › Show Tour. Return or → moves on, ← goes back, Esc skips; ⌘⏎ approves the sample card.
struct MeetBlinkTour: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("tour.v1.done") private var tourDone = false
    @State private var chapter = 0
    @State private var forward = true
    @State private var approved = false
    @FocusState private var focused: Bool

    private static let count = 7

    var body: some View {
        ZStack {
            HorizonGlow().ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip Tour", action: finish)
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .keyboardShortcut(.cancelAction)
                        .opacity(chapter == Self.count - 1 ? 0 : 1)
                }
                .padding(.horizontal, 32).padding(.top, 22)
                Spacer(minLength: 0)
                Group {
                    if chapter == 0 { intro } else { page(chapter) }
                }
                .id(chapter)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .offset(x: forward ? 60 : -60).combined(with: .opacity),
                    removal: .offset(x: forward ? -60 : 60).combined(with: .opacity)))
                Spacer(minLength: 0)
                footer.padding(.horizontal, 40).padding(.bottom, 30)
            }
        }
        .frame(minWidth: 900, idealWidth: 1080, minHeight: 600, idealHeight: 680)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        // Closed any way (Skip, Start, the red button, ⌘W): seen. Help › Show Tour resets it.
        .onDisappear { tourDone = true }
        .onChange(of: chapter) {
            AccessibilityNotification.Announcement("Chapter \(chapter + 1) of \(Self.count). \(chapter == 0 ? "Meet Blink." : Self.chapters[chapter - 1].title.replacingOccurrences(of: "\n", with: " "))").post()
        }
        .onKeyPress(.rightArrow) { go(1); return .handled }
        .onKeyPress(.leftArrow) { go(-1); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meet Blink, chapter \(chapter + 1) of \(Self.count)")
    }

    private func finish() { dismissWindow(id: "tour") }

    // MARK: Chapters

    private var intro: some View {
        VStack(spacing: 34) {
            BlinkEyes(mood: .celebrate)
                .frame(width: 220, height: 88)
                .shadow(color: .white.opacity(0.35), radius: 40)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                Text("Meet Blink.")
                    .font(.system(size: 76, weight: .bold))
                    .tracking(-2)
                Text("Your day, one glance up.")
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(.white.opacity(0.85))
                Text("A small assistant that lives in your notch. It knows your calendar, mail, tasks and money, and it asks before it acts.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 520)
            }
            Button { go(1) } label: {
                Text("Take the Tour").font(.system(size: 15, weight: .semibold)).padding(.horizontal, 24).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .background(.white, in: .capsule)
            .foregroundStyle(.black)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func page(_ index: Int) -> some View {
        let c = Self.chapters[index - 1]
        return HStack(alignment: .center, spacing: 64) {
            VStack(alignment: .leading, spacing: 0) {
                Text(c.kicker.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color.accentColor)
                Text(c.title)
                    .font(.system(size: 46, weight: .bold))
                    .tracking(-1.2)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text(c.line)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                if !c.keys.isEmpty || c.action != nil {
                    HStack(spacing: 8) {
                        ForEach(c.keys, id: \.self) { KeyCap(text: $0) }
                        if let action = c.action {
                            Button(c.actionTitle) { model.notchAction?(action) }
                                .buttonStyle(.plain)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(.white.opacity(0.1), in: .capsule)
                                .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                                .padding(.leading, c.keys.isEmpty ? 0 : 8)
                        }
                    }
                    .padding(.top, 28)
                }
            }
            .frame(width: 360, alignment: .leading)
            scene(index)
                .frame(width: 520, height: 340)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func scene(_ index: Int) -> some View {
        switch index {
        case 1: NotchScene()
        case 2: TypeScene()
        case 3: ApproveScene(approved: $approved)
        case 4: BarScene()
        case 5: ClipboardSearchScene()
        default: FinaleScene()
        }
    }

    private var footer: some View {
        HStack {
            Button { go(-1) } label: { Label("Back", systemImage: "chevron.left").font(.system(size: 13, weight: .medium)) }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.55))
                .opacity(chapter == 0 ? 0 : 1)
                .disabled(chapter == 0)
                .frame(width: 140, alignment: .leading)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<Self.count, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(i == chapter ? 0.95 : 0.22))
                        .frame(width: i == chapter ? 24 : 6, height: 6)
                }
            }
            .animation(reduceMotion ? nil : Tokens.Motion.content.animation, value: chapter)
            .accessibilityHidden(true)
            Spacer()
            Group {
                if chapter > 0 {
                    Button { chapter == Self.count - 1 ? finish() : go(1) } label: {
                        Text(chapter == Self.count - 1 ? "Start Using Blink" : "Continue")
                            .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 20).padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .background(.white, in: .capsule)
                    .foregroundStyle(.black)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 140, alignment: .trailing)
        }
        .overlay {
            // ⌘⏎ approves the sample card, as it approves real ones in the notch.
            if chapter == 3 {
                Button("Approve the Sample Card") { withAnimation(Tokens.Motion.success.animation) { approved = true } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .opacity(0)
            }
        }
    }

    private func go(_ step: Int) {
        let next = min(max(chapter + step, 0), Self.count - 1)
        guard next != chapter else { return }
        forward = step > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)) { chapter = next }
    }

    private struct Chapter {
        let kicker: String
        let title: String
        let line: String
        var keys: [String] = []
        var action: AppModel.NotchAction?
        var actionTitle = "Try It"
    }

    private static let chapters: [Chapter] = [
        Chapter(kicker: "Your day at a glance", title: "It lives in\nyour notch.",
                line: "Ten minutes before a meeting, Blink peeks out with Join one click away. Click the notch any time to see the rest of your day.",
                action: .open, actionTitle: "Show Me"),
        Chapter(kicker: "Just type", title: "Say it the way\nyou'd say it.",
                line: "“Remind me to stretch in 2 minutes.” “Task: send the invoice Friday.” Blink understands, and it's done before you look back.",
                keys: ["⌃", "⌥", "Space"], action: .chat),
        Chapter(kicker: "You're in charge", title: "It asks\nbefore it acts.",
                line: "When Blink wants to add, move or send something, it shows you first. One press approves. Nothing changes behind your back.",
                keys: ["⌘", "⏎"]),
        Chapter(kicker: "One bar, every page", title: "Type anywhere\nin the app.",
                line: "The bar at the bottom of every page knows where you are: spending on Money, tasks on Tasks, notes on Notes, a question anywhere else.",
                keys: ["⌘", "L"]),
        Chapter(kicker: "Everything you copied", title: "Find it again\nin a second.",
                line: "Blink keeps what you copy on this Mac, and finds any note, task or reminder as you type. Passwords are never kept.",
                keys: ["⌃", "⌥", "V"], action: .clipboard, actionTitle: "Open Clipboard"),
        Chapter(kicker: "You're all set", title: "That's Blink.",
                line: "Press ⌘/ any time to see every shortcut, and Help › Show Tour to watch this again. Your day is one glance up.",
                keys: ["⌘", "/"]),
    ]
}

// MARK: The screen

/// A key on a Mac keyboard, for the shortcut each chapter teaches.
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .frame(minWidth: 22)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(
                LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.4), radius: 0, y: 1.5)
    }
}

/// A MacBook screen: the black bezel, a soft wallpaper, the menu bar with its clock, and the notch, which holds `notch`
/// and grows to fit it. `desktop` sits below the menu bar.
private struct MacScreen<Notch: View, Desktop: View>: View {
    @ViewBuilder let notch: Notch
    @ViewBuilder let desktop: Desktop

    var body: some View {
        ZStack(alignment: .top) {
            // The wallpaper: the night-blue Blink uses everywhere, a little lighter in the middle.
            LinearGradient(colors: [Color(white: 0.05), Color.blue.opacity(0.55), Color.cyan.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(RadialGradient(colors: [.white.opacity(0.10), .clear], center: .center, startRadius: 10, endRadius: 320))
            VStack(spacing: 0) {
                menuBar
                desktop.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            notch
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
                .frame(minWidth: 150, minHeight: 26)
                .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        }
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .padding(9)
        .background(.black, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.55), radius: 40, y: 24)
    }

    private var menuBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo").font(.system(size: 11, weight: .semibold))
            Text("Blink").font(.system(size: 11, weight: .bold))
            ForEach(["File", "Edit", "View", "Window"], id: \.self) { Text($0).font(.system(size: 11)) }
            Spacer()
            Image(systemName: "wifi").font(.system(size: 10, weight: .semibold))
            Text("Thu 10:50").font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.black.opacity(0.25))
    }
}

/// A card on the screen, frosted like a macOS panel.
private struct ScreenCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

// MARK: Scenes

/// Chapter 1: the notch rests, peeks with a meeting, then opens on the day.
private struct NotchScene: View {
    enum Phase: CaseIterable { case rest, peek, open }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion { screen(.open) } else {
            PhaseAnimator(Phase.allCases) { phase in screen(phase) } animation: { phase in
                switch phase {
                case .rest: Tokens.Motion.close.animation.delay(1.6)
                case .peek: Tokens.Motion.peek.animation.delay(1.4)
                case .open: Tokens.Motion.open.animation.delay(1.6)
                }
            }
        }
    }

    private func screen(_ phase: Phase) -> some View {
        MacScreen {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    BlinkEyes(mood: phase == .rest ? .idle : .headsUp).frame(width: 40, height: 16)
                    if phase != .rest {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Design review").font(.system(size: 13, weight: .semibold))
                            Text("in 10 minutes · Room 4").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer(minLength: 10)
                        Text("Join").font(.system(size: 12, weight: .bold)).padding(.horizontal, 12).padding(.vertical, 5)
                            .background(.white, in: .capsule).foregroundStyle(.black)
                    }
                }
                if phase == .open {
                    Divider().overlay(.white.opacity(0.15))
                    ForEach([("13:30", "Lunch with Sam"), ("16:00", "Send the invoice"), ("18:00", "Gym")], id: \.0) { time, what in
                        HStack(spacing: 12) {
                            Text(time).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                            Text(what).font(.system(size: 13))
                        }
                    }
                }
            }
            .frame(width: phase == .rest ? 70 : 300, alignment: .leading)
        } desktop: {
            Color.clear
        }
    }
}

/// Chapter 2: words typed in the notch become a reminder.
private struct TypeScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let line = "remind me to stretch in 2 minutes"

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            // A 6-second loop: type for 2.6 s, show the reminder, hold, start again.
            let t = reduceMotion ? 6 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6)
            let shown = String(line.prefix(Int(min(t / 2.6, 1) * Double(line.count))))
            MacScreen {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        BlinkEyes(mood: t > 2.8 ? .done : .listening).frame(width: 40, height: 16)
                        Text(shown.isEmpty ? " " : shown).font(.system(size: 13))
                        + Text(t < 2.6 ? "▏" : "").font(.system(size: 13)).foregroundStyle(Color.accentColor)
                    }
                    if t > 2.8 {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Stretch").font(.system(size: 13, weight: .semibold))
                                Text("Reminder · in 2 minutes").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .padding(10)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .frame(width: 300, alignment: .leading)
                .animation(reduceMotion ? nil : Tokens.Motion.success.animation, value: t > 2.8)
            } desktop: {
                Color.clear
            }
        }
    }
}

/// Chapter 3: a sample card to approve, right here (nothing real is added).
private struct ApproveScene: View {
    @Binding var approved: Bool

    var body: some View {
        MacScreen {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    BlinkEyes(mood: approved ? .celebrate : .concerned).frame(width: 40, height: 16)
                    Text(approved ? "Added to Reminders." : "Can I add this?").font(.system(size: 13, weight: .semibold))
                }
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pay rent").font(.system(size: 13, weight: .semibold))
                        Text("1 Nov, 9:00 · from your landlord's mail").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(10)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
                if approved {
                    Label("Approved", systemImage: "checkmark.circle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    HStack {
                        Text("Not Now").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Button { withAnimation(Tokens.Motion.success.animation) { approved = true } } label: {
                            Text("Approve  ⌘⏎").font(.system(size: 12, weight: .bold)).padding(.horizontal, 12).padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .background(.white, in: .capsule)
                        .foregroundStyle(.black)
                    }
                }
            }
            .frame(width: 300, alignment: .leading)
        } desktop: {
            Color.clear
        }
    }
}

/// Chapter 4: a Blink window with the glass bar, showing what each page's bar takes.
private struct BarScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let examples: [(String, String, String)] = [
        ("Money", "eurosign.circle", "lunch 8.50, bus 3"),
        ("Tasks", "checkmark.circle", "send the invoice Friday"),
        ("Notes", "square.and.pencil", "Ideas for the launch"),
        ("Today", "sparkles", "what's left today?"),
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2.2)) { context in
            let i = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 2.2) % examples.count
            let example = examples[i]
            MacScreen {
                BlinkEyes(mood: .idle).frame(width: 40, height: 16)
            } desktop: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(example.0).font(.system(size: 24, weight: .bold)).tracking(-0.5)
                    ForEach(0..<3, id: \.self) { row in
                        RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.10)).frame(width: [220, 180, 200][row], height: 12)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: example.1).foregroundStyle(.white.opacity(0.6))
                        Text(example.2).font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 18)).foregroundStyle(Color.accentColor)
                    }
                    .padding(.leading, 14).padding(.trailing, 7).padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                }
                .padding(22)
                .padding(.top, 20)
                .background(.black.opacity(0.35), in: .rect(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 26).padding(.vertical, 18)
            }
            .animation(reduceMotion ? nil : Tokens.Motion.content.animation, value: i)
        }
    }
}

/// Chapter 5: the clipboard history and search, as panels on the screen.
private struct ClipboardSearchScene: View {
    var body: some View {
        MacScreen {
            BlinkEyes(mood: .idle).frame(width: 40, height: 16)
        } desktop: {
            HStack(alignment: .top, spacing: 12) {
                panel(title: "Clipboard", symbol: "doc.on.clipboard", rows: ["Invoice #2041 · €480", "blinkk.app/install", "Q4 plan, meeting notes"])
                panel(title: "Search", symbol: "magnifyingglass", rows: ["Note · Launch ideas", "Task · Send the invoice", "Reminder · Pay rent"])
            }
            .padding(.horizontal, 22).padding(.top, 34).padding(.bottom, 20)
        }
    }

    private func panel(title: String, symbol: String, rows: [String]) -> some View {
        ScreenCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
                ForEach(rows, id: \.self) { row in
                    Text(row).font(.system(size: 12)).lineLimit(1)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

/// Chapter 6: Blink, happy, at rest in the notch.
private struct FinaleScene: View {
    var body: some View {
        MacScreen {
            BlinkEyes(mood: .celebrate).frame(width: 64, height: 26)
        } desktop: {
            VStack(spacing: 6) {
                Text("⌘/").font(.system(size: 40, weight: .bold)).tracking(-1)
                Text("every shortcut, any time").font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}
#endif
