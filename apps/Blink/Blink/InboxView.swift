// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI

/// Inbox (Phase 5): mail the server checked and sorted, by mailbox, searchable. Important first; each section folds.
/// Click a mail to read it on the right; tick several for Done or teaching at once; the keyboard works too
/// (↑↓ move, Space opens, E clears, R reply, I important, ⌘A selects all). Each mail's next steps (an event, a deadline,
/// a to-do, a detail) become a calendar event, reminder, task or note with one tap.
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("inbox.account") private var account = "all"
    @AppStorage("open.inbox.important") private var importantOpen = true
    @AppStorage("open.inbox.reply") private var replyOpen = true
    @AppStorage("open.inbox.rest") private var restOpen = true
    @AppStorage("open.inbox.newsletter") private var newsletterOpen = false
    @State private var query = ""
    @State private var selected: Set<String> = []
    @State private var focused: String?
    @State private var reading: String?
    @FocusState private var pageFocused: Bool

    var body: some View {
        @Bindable var model = model
        let shown = model.emails.filter(matches)
        let important = shown.filter { $0.triage == .important }
        let reply = shown.filter { $0.triage == .normal && $0.needsReply }
        let rest = shown.filter { $0.triage == .normal && !$0.needsReply }
        let newsletters = shown.filter { $0.triage == .newsletter }
        // The rows the keyboard walks through: what's visible, top to bottom.
        let order = (importantOpen ? important : []) + (replyOpen ? reply : []) + (restOpen ? rest : []) + (newsletterOpen ? newsletters : [])
        ScrollViewReader { proxy in
            DashPage("Inbox", summary: summary(important: important.count)) {
                HStack {
                    if accounts.count > 1 {
                        Picker("Mailbox", selection: $account) {
                            Text("All").tag("all")
                            ForEach(accounts, id: \.self) { Text(EmailMessage.accountName($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Spacer()
                    PageSearchField(prompt: "Search mail", text: $query)
                }
                if let problem = model.mailProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                ForEach(model.mailStates.filter { $0.lastError != nil }, id: \.account) { state in
                    Label("\(EmailMessage.accountName(state.account)): \(state.lastError ?? "")", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                if let sending = model.sendingNow {
                    DashCard {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Sending “\(sending.payload.subject ?? sending.title)”…").lineLimit(1)
                            Spacer()
                            Button("Cancel") { Task { await model.cancelSend(sending) } }
                        }
                    }
                }
                let scheduled = model.outbox.filter { $0.id != model.sendingNow?.id }
                if !scheduled.isEmpty {
                    FoldingCard(key: "inbox.outbox", title: "Scheduled to send", count: scheduled.count) {
                        CardRows(items: scheduled) { OutboxRow(action: $0) }
                    }
                }
                if !selected.isEmpty { bulkBar(order: order) }
                if model.emails.isEmpty {
                    EmptyCard(symbol: "envelope", title: model.mailStates.isEmpty ? "Mail isn't connected yet" : "Nothing new",
                              message: model.mailStates.isEmpty
                                ? "Add your mail passwords to your server's secrets (GMAIL_ADDRESS + GMAIL_APP_PASSWORD, ICLOUD_ADDRESS + ICLOUD_APP_PASSWORD, UNI_ADDRESS + UNI_PASSWORD), then press Check Now."
                                : "Blink checks your mail every 5 minutes. Important mail shows here and in the notch.",
                              actionTitle: "Check Now", action: { Task { await model.syncMail() } })
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                section("important", "Important", important)
                section("reply", "Needs a reply", reply)
                section("rest", "Everything else", rest)
                section("newsletter", "Not important", newsletters, openByDefault: false)
            }
            .onChange(of: focused) { _, id in if let id { withAnimation(.snappy) { proxy.scrollTo(id) } } }
        }
        .focusable()
        .focused($pageFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handle(press, order: order) }
        // ⌘A is Edit › Select All, which reaches the page as a command, not a key press.
        .onCommand(#selector(NSResponder.selectAll(_:))) { selected = Set(order.map(\.id)) }
        .onAppear { pageFocused = true }
        .inspector(isPresented: Binding(get: { reading != nil }, set: { if !$0 { reading = nil } })) {
            if let message = model.emails.first(where: { $0.id == reading }) {
                MailReader(message: message, close: { reading = nil })
                    .inspectorColumnWidth(min: 320, ideal: 400, max: 560)
            } else {
                ContentUnavailableView("Cleared", systemImage: "checkmark.circle", description: Text("This email is no longer in your inbox."))
            }
        }
        .sheet(item: $model.reviewing) { ReplyReviewSheet(review: $0) }
        .toolbar {
            Button { Task { await model.syncMail() } } label: {
                if model.syncingMail { ProgressView().controlSize(.small) } else { Label("Check Mail", systemImage: "envelope.arrow.triangle.branch") }
            }
            .disabled(model.syncingMail)
            .help("Check all your mailboxes now")
        }
        .task {
            await model.loadMail()
            // Seen here: the notch stops announcing these.
            for message in model.importantMail where message.status == .new { await model.setStatus(.seen, of: message) }
        }
        .onChange(of: model.emails) { _, emails in
            // Selections and focus never point at mail that's gone (done, sent, or done elsewhere).
            let ids = Set(emails.map(\.id))
            selected.formIntersection(ids)
            if let f = focused, !ids.contains(f) { focused = nil }
        }
    }

    /// Acts on the ticked mails at once; teaching applies to each sender, Done to each mail, all undoable.
    private func bulkBar(order: [EmailMessage]) -> some View {
        // Only ticked mail you can see: a search or a folded section never hides what Done acts on.
        let picked = order.filter { selected.contains($0.id) }
        return DashCard {
            HStack(spacing: 10) {
                Text("\(picked.count) selected").font(.headline)
                Button(picked.count == order.count ? "Select None" : "Select All") {
                    selected = picked.count == order.count ? [] : Set(order.map(\.id))
                }
                Spacer()
                Button("Clear") { Task { await model.finish(picked); selected = [] } }
                    .help("Clear these from Blink's inbox. Anything you added from them stays.")
                Menu("Teach Blink") {
                    Button("Mark Important", systemImage: "exclamationmark.circle") { teach(.important, picked) }
                    Button("Not Important", systemImage: "arrow.down.circle") { teach(.newsletter, picked) }
                    Text("Applies to all mail from these senders")
                }
                .fixedSize()
                Button("Clear", systemImage: "xmark") { selected = [] }.labelStyle(.iconOnly).help("Clear the selection")
            }
            .controlSize(.small)
        }
    }

    private func teach(_ verdict: SenderVerdict, _ picked: [EmailMessage]) {
        // One per sender: teaching is per sender anyway.
        let senders = Dictionary(grouping: picked, by: \.senderKey).compactMap(\.value.first)
        Task {
            for message in senders { await model.teach(verdict, for: message) }
            selected = []
        }
    }

    /// The keyboard: ↑↓ move, Space or Return opens, E done, R reply, I important, X ticks, ⌘A selects all, Esc clears.
    private func handle(_ press: KeyPress, order: [EmailMessage]) -> KeyPress.Result {
        let at = order.firstIndex { $0.id == focused }
        let current = at.map { order[$0] }
        switch press.key {
        case .downArrow, .upArrow:
            guard !order.isEmpty else { return .ignored }
            let step = press.key == .downArrow ? 1 : -1
            focused = order[at.map { min(max($0 + step, 0), order.count - 1) } ?? 0].id
            if reading != nil { reading = focused }
            return .handled
        case .space, .return:
            guard let current else { return .ignored }
            reading = reading == current.id ? nil : current.id
            return .handled
        case .escape:
            if !selected.isEmpty { selected = [] } else if reading != nil { reading = nil } else { return .ignored }
            return .handled
        default: break
        }
        if press.modifiers.isEmpty, press.characters == "e", !selected.isEmpty {
            let picked = order.filter { selected.contains($0.id) }
            Task { await model.finish(picked); selected = [] }
            return .handled
        }
        guard press.modifiers.isEmpty, let current else { return .ignored }
        switch press.characters {
        case "e":
            // The next row takes focus, so E, E, E clears a run of mail.
            if let at, order.count > 1 { focused = order[at + 1 < order.count ? at + 1 : at - 1].id }
            if reading != nil { reading = focused }
            Task { await model.finish([current]) }
        case "r": Task { await model.reviewReply(to: current) }
        case "i": Task { await model.teach(.important, for: current) }
        case "x": if selected.contains(current.id) { selected.remove(current.id) } else { selected.insert(current.id) }
        default: return .ignored
        }
        return .handled
    }

    /// Mailboxes that are connected or have mail, in a fixed order.
    private var accounts: [String] {
        let known = Set(model.mailStates.map(\.account) + model.emails.map(\.account))
        return ["gmail", "icloud", "uni"].filter(known.contains)
    }

    private func matches(_ message: EmailMessage) -> Bool {
        guard account == "all" || message.account == account else { return false }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [message.sender, message.fromAddr, message.subject, message.summary].contains { $0.localizedStandardContains(q) }
    }

    @ViewBuilder
    private func section(_ key: String, _ title: String, _ list: [EmailMessage], openByDefault: Bool = true) -> some View {
        if !list.isEmpty {
            FoldingCard(key: "inbox.\(key)", title: title, count: list.count, openByDefault: openByDefault) {
                CardRows(items: list) { message in
                    MailRow(message: message, focused: focused == message.id, reading: reading == message.id,
                            selected: Binding(get: { selected.contains(message.id) },
                                              set: { if $0 { selected.insert(message.id) } else { selected.remove(message.id) } }),
                            open: { focused = message.id; reading = message.id; pageFocused = true })
                        .id(message.id)
                }
            }
        }
    }

    private func summary(important: Int) -> String {
        let checked = model.mailStates.compactMap(\.lastCheckedAt).max()
        let when = checked.map { "checked \($0.formatted(.relative(presentation: .named)))" } ?? "not checked yet"
        return important == 0 ? "Nothing important · \(when)" : "\(important) important · \(when)"
    }
}

/// Mail approved and waiting for its time; cancel until it goes.
private struct OutboxRow: View {
    @Environment(AppModel.self) private var model
    let action: BlinkAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "paperplane").foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.payload.subject ?? action.title).lineLimit(1)
                Text("To \(action.payload.to ?? "")").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let at = action.payload.sendAt {
                Text(at, format: .dateTime.weekday(.abbreviated).day().month().hour().minute()).font(.callout).foregroundStyle(.secondary)
            }
            Button("Cancel") { Task { await model.cancelSend(action) } }.controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }
}

/// One email: a tick box, sender, subject, Blink's one-line summary and why it matters, its next steps as chips; Reply
/// (review and send), Done, and a menu to mark it important or not. Clicking it opens it in the reading pane.
struct MailRow: View {
    @Environment(AppModel.self) private var model
    let message: EmailMessage
    var focused = false
    var reading = false
    @Binding var selected: Bool
    var open: () -> Void = {}
    @State private var writingNote = false
    @State private var note = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Select", isOn: $selected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Select: \(message.sender), \(message.subject)")
                .padding(.top, 2)
            Image(systemName: message.triage == .important ? "exclamationmark.circle.fill" : message.status == .drafted ? "envelope.open" : "envelope")
                .foregroundStyle(message.triage == .important ? Color.red : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(message.sender).font(message.status == .new ? .headline : .body.weight(.medium)).lineLimit(1)
                        if message.account == "uni" {
                            Text("Uni").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(.quaternary, in: .capsule)
                        }
                        if !message.reason.isEmpty {
                            Text(message.reason).font(.caption.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.red.opacity(0.15), in: .capsule).foregroundStyle(.red)
                        }
                        Spacer()
                        if let at = message.receivedAt {
                            Text(at, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(message.subject).lineLimit(1)
                    if !message.summary.isEmpty { Text(message.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                }
                .contentShape(.rect)
                .onTapGesture(perform: open)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Read", open)
                NextStepChips(message: message)
                HStack(spacing: 10) {
                    Button {
                        Task { await model.reviewReply(to: message) }
                    } label: {
                        if model.draftingMail.contains(message.id) { ProgressView().controlSize(.small) }
                        else { Text(message.status == .drafted ? "Review & Send" : "Reply") }
                    }
                    .disabled(model.draftingMail.contains(message.id))
                    Button("With a Note…") { writingNote = true }
                        .popover(isPresented: $writingNote, arrowEdge: .bottom) { notePopover }
                    Button("Clear") { Task { await model.finish([message]) } }
                        .help("Clear this from Blink's inbox. Anything you added from it stays.")
                    Menu("More", systemImage: "ellipsis.circle") { moreItems }
                        .labelStyle(.iconOnly)
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Teach Blink, or open in Apple Mail")
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(6)
        .background(reading ? Color.accentColor.opacity(0.12) : focused ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .contextMenu { moreItems }
    }

    /// Teaching: the mark applies to this sender from now on, and the server's sorting learns from it.
    @ViewBuilder
    private var moreItems: some View {
        if message.triage != .important {
            Button("Mark Important", systemImage: "exclamationmark.circle") { Task { await model.teach(.important, for: message) } }
        }
        if message.triage != .newsletter {
            Button("Not Important", systemImage: "arrow.down.circle") { Task { await model.teach(.newsletter, for: message) } }
        }
        Text("Applies to all mail from \(message.fromAddr)")
        Divider()
        if let url = message.mailURL { Button("Open in Apple Mail", systemImage: "envelope") { NSWorkspace.shared.open(url) } }
    }

    private var notePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What should the reply say?").font(.headline)
            TextField("e.g. Yes to Thursday 10:00, ask for the address", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...5).frame(width: 320)
            Button("Write Draft") {
                writingNote = false
                Task { await model.reviewReply(to: message, note: note, reuse: false) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
    }
}
/// A mail's next steps as small buttons: "Add to Calendar: Interview · Thu 21 Oct 15:00". One tap saves it (with Undo
/// in the window and the notch); a saved one shows a tick.
struct NextStepChips: View {
    @Environment(AppModel.self) private var model
    let message: EmailMessage

    var body: some View {
        let steps = Array(message.nextSteps.enumerated())
        if !steps.isEmpty {
            HStack(spacing: 6) {
                ForEach(steps, id: \.offset) { index, step in
                    let saved = model.savedSteps.contains("\(message.id)#\(index)")
                    Button { Task { await model.save(step, from: message, index: index) } } label: {
                        Label(Self.text(step), systemImage: saved ? "checkmark" : Self.symbol(step.kind))
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(saved ? .green : .blue)
                    .disabled(saved)
                    .help(saved ? "Added" : Self.verb(step.kind))
                    .accessibilityLabel(saved ? "Added: \(step.title)" : "\(Self.verb(step.kind)): \(Self.text(step))")
                }
            }
        }
    }

    static func symbol(_ kind: MailAction.Kind) -> String {
        switch kind {
        case .event: "calendar.badge.plus"
        case .deadline: "bell.badge"
        case .task: "checklist"
        case .note: "note.text.badge.plus"
        }
    }

    static func verb(_ kind: MailAction.Kind) -> String {
        switch kind {
        case .event: "Add to Calendar"
        case .deadline: "Remind Me"
        case .task: "Add Task"
        case .note: "Save to Notes"
        }
    }

    /// "Interview · Thu 21 Oct, 15:00", "Pay rent · Mon 20 Oct", "Booking ref LH4XK2".
    static func text(_ step: MailAction) -> String {
        guard let start = step.start else { return step.title }
        let when = step.allDay ? start.formatted(.dateTime.weekday(.abbreviated).day().month())
            : start.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute())
        return "\(step.title) · \(when)"
    }
}

/// The reading pane: the whole mail, fetched from the mailbox when opened (never stored), with its next steps and the
/// same Reply and Done as the row.
struct MailReader: View {
    @Environment(AppModel.self) private var model
    let message: EmailMessage
    let close: () -> Void
    @State private var text: String?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.subject.isEmpty ? "(No subject)" : message.subject).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text("\(message.sender) <\(message.fromAddr)>").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    if let at = message.receivedAt {
                        Text("\(EmailMessage.accountName(message.account)) · \(at.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !message.summary.isEmpty {
                    Label(message.summary, systemImage: "sparkles").font(.callout)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                }
                NextStepChips(message: message)
                HStack(spacing: 10) {
                    Button(message.status == .drafted ? "Review & Send" : "Reply") { Task { await model.reviewReply(to: message) } }
                        .disabled(model.draftingMail.contains(message.id))
                    Button("Clear") { Task { await model.finish([message]); close() } }
                        .help("Clear this from Blink's inbox. Anything you added from it stays.")
                    if let url = message.mailURL { Button("Open in Apple Mail") { NSWorkspace.shared.open(url) } }
                }
                .controlSize(.small)
                Divider()
                if let text {
                    Text(text.isEmpty ? "This email has no text." : text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                } else if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    ProgressView("Opening…").frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .task(id: message.id) {
            text = nil
            problem = nil
            // Walking through mail with ↓ opens only where you stop, not one mailbox login per mail passed.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do { text = try await model.read(message) } catch let error as BlinkServer.ChatProblem { problem = error.message } catch {
                problem = "Can't reach your server right now."
            }
        }
    }
}
#endif
