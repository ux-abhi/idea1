// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI

/// Inbox, laid out like Mail: the sorted list on the left, the open mail on the right, and Reply, Done and Check Mail
/// in the toolbar. The list is a native one, so arrows, Shift-click, ⌘A and the Delete key work as everywhere on the
/// Mac; E marks done, R replies. Teaching Blink about a sender is in the right-click menu. A mail's next steps (an event, a deadline, a to-do,
/// a detail) become a calendar event, reminder, task or note with one click in the reading pane.
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("inbox.account") private var account = "all"
    @AppStorage("open.inbox.newsletter") private var newsletterOpen = false
    @State private var query = ""
    @State private var selection: Set<String> = []

    var body: some View {
        @Bindable var model = model
        let shown = model.emails.filter(matches)
        let picked = shown.filter { selection.contains($0.id) }
        HSplitView {
            list(shown)
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)
            reader(picked)
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search mail")
        .toolbar { toolbar(picked) }
        .sheet(item: $model.reviewing) { ReplyReviewSheet(review: $0) }
        .task {
            await model.loadMail()
            // Seen here: the notch stops announcing these.
            for message in model.importantMail where message.status == .new { await model.setStatus(.seen, of: message) }
        }
        .onChange(of: model.emails) { _, emails in selection.formIntersection(emails.map(\.id)) }
    }

    // MARK: The list

    private func list(_ shown: [EmailMessage]) -> some View {
        let important = shown.filter { $0.triage == .important }
        let reply = shown.filter { $0.triage == .normal && $0.needsReply }
        let rest = shown.filter { $0.triage == .normal && !$0.needsReply }
        let newsletters = shown.filter { $0.triage == .newsletter }
        return List(selection: $selection) {
            section("Important", important)
            section("To Reply", reply)
            section("Other", rest)
            if !newsletters.isEmpty {
                Section(isExpanded: $newsletterOpen) {
                    ForEach(newsletters) { row($0) }
                } header: {
                    Text("Low Priority · \(newsletters.count)")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: String.self) { ids in menu(for: ids) }
        .onDeleteCommand { clear(selection) }
        .onKeyPress(characters: .init(charactersIn: "er"), phases: .down) { press in
            guard !selection.isEmpty, press.modifiers.isEmpty else { return .ignored }
            if press.characters == "e" { clear(selection) } else if let one = selected.first, selection.count == 1 { Task { await model.reviewReply(to: one) } }
            return .handled
        }
        .overlay {
            if model.emails.isEmpty {
                emptyState
            } else if shown.isEmpty {
                if query.isEmpty { ContentUnavailableView("No mail here", systemImage: "tray") } else { ContentUnavailableView.search(text: query) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { banners }
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [EmailMessage]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { row($0) }
            }
        }
    }

    private func row(_ message: EmailMessage) -> some View {
        MailListRow(message: message)
            .tag(message.id)
            .accessibilityAction(named: "Reply") { Task { await model.reviewReply(to: message) } }
            .accessibilityAction(named: "Done") { clear([message.id]) }
    }

    private var selected: [EmailMessage] { model.emails.filter { selection.contains($0.id) } }

    @ViewBuilder
    private var emptyState: some View {
        if model.mailStates.isEmpty {
            ContentUnavailableView {
                Label("Connect your mail", systemImage: "envelope")
            } description: {
                Text("Add Gmail, iCloud or another mailbox. Blink then checks it every 5 minutes and sorts what matters.")
            } actions: {
                Button("Connect Mail…") { model.openSettings("connections") }.buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView("All caught up", systemImage: "checkmark.circle",
                                   description: Text("Blink checks your mail every 5 minutes. Important mail shows here and in the notch."))
        }
    }

    /// Problems, a send in progress and scheduled mail: thin bars above the list, only when there's something.
    @ViewBuilder
    private var banners: some View {
        let scheduled = model.outbox.filter { $0.id != model.sendingNow?.id }
        let errors = model.mailStates.filter { $0.lastError != nil }
        if model.mailProblem != nil || !errors.isEmpty || model.sendingNow != nil || !scheduled.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let problem = model.mailProblem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(1) }
                if !errors.isEmpty {
                    HStack {
                        Label("\(errors.map { EmailMessage.accountName($0.account) }.formatted()) can't connect", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).lineLimit(1)
                            .help(errors.compactMap(\.lastError).joined(separator: "\n"))
                        Spacer()
                        Button("Fix…") { model.openSettings("connections") }.buttonStyle(.link)
                    }
                }
                if let sending = model.sendingNow {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Sending “\(sending.payload.subject ?? sending.title)”…").lineLimit(1)
                        Spacer()
                        Button("Cancel") { Task { await model.cancelSend(sending) } }.controlSize(.small)
                    }
                }
                if !scheduled.isEmpty {
                    Menu {
                        ForEach(scheduled) { action in
                            Button("Cancel “\(action.payload.subject ?? action.title)”\(action.payload.sendAt.map { " · \($0.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" } ?? "")") {
                                Task { await model.cancelSend(action) }
                            }
                        }
                    } label: {
                        Label("\(scheduled.count) scheduled to send", systemImage: "paperplane")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .font(.callout)
            .padding(10)
            .background(.bar)
        }
    }

    // MARK: Reading pane

    @ViewBuilder
    private func reader(_ picked: [EmailMessage]) -> some View {
        switch picked.count {
        case 0:
            ContentUnavailableView("No mail selected", systemImage: "envelope.open",
                                   description: Text("Select a mail to read it."))
        case 1:
            MailReader(message: picked[0], close: { selection = [] })
        default:
            ContentUnavailableView {
                Label("\(picked.count) mails selected", systemImage: "tray.full")
            } actions: {
                Button("Mark All Done") { clear(selection) }.buttonStyle(.borderedProminent)
                Menu("Sender") { teachItems(picked) }.fixedSize()
            }
        }
    }

    // MARK: Actions

    @ToolbarContentBuilder
    private func toolbar(_ picked: [EmailMessage]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if accounts.count > 1 {
                Picker("Mailbox", selection: $account) {
                    Text("All Mailboxes").tag("all")
                    ForEach(accounts, id: \.self) { Text(EmailMessage.accountName($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { if let one = picked.first { Task { await model.reviewReply(to: one) } } } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            .disabled(picked.count != 1)
            .help("Reply (R)")
            Button { clear(selection) } label: { Label("Done", systemImage: "archivebox") }
                .disabled(picked.isEmpty)
                .help("Done: off Blink's inbox (E). Anything you added from it stays.")
            Button { Task { await model.syncMail() } } label: {
                Label("Check Mail", systemImage: "arrow.clockwise").symbolEffect(.rotate, isActive: model.syncingMail)
            }
            .disabled(model.syncingMail)
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("Check all your mailboxes now (⇧⌘N)")
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<String>) -> some View {
        let picked = model.emails.filter { ids.contains($0.id) }
        if picked.count == 1, let one = picked.first {
            Button("Reply") { Task { await model.reviewReply(to: one) } }
            if let url = one.mailURL { Button("Open in Apple Mail") { NSWorkspace.shared.open(url) } }
            Divider()
        }
        Button("Done") { clear(ids) }
        Menu("Sender") { teachItems(picked) }
    }

    @ViewBuilder
    private func teachItems(_ picked: [EmailMessage]) -> some View {
        Section("All mail from \(picked.count == 1 ? picked[0].fromAddr : "these senders")") {
            Button("Always Important", systemImage: "exclamationmark.circle") { teach(.important, picked) }
            Button("Never Important", systemImage: "arrow.down.circle") { teach(.newsletter, picked) }
        }
    }

    private func clear(_ ids: Set<String>) {
        let picked = model.emails.filter { ids.contains($0.id) }
        guard !picked.isEmpty else { return }
        Task { await model.finish(picked) }
        selection.subtract(ids)
    }

    private func teach(_ verdict: SenderVerdict, _ picked: [EmailMessage]) {
        // One per sender: teaching is per sender anyway.
        let senders = Dictionary(grouping: picked, by: \.senderKey).compactMap(\.value.first)
        Task { for message in senders { await model.teach(verdict, for: message) } }
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
}

/// One mail in the list, like Mail: who and when, the subject, and Blink's one-line summary. Unread shows a dot and a
/// bolder sender; a small sparkle means Blink found next steps in it.
private struct MailListRow: View {
    let message: EmailMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(message.status == .new ? Color.accentColor : .clear)
                .frame(width: 7, height: 7)
                .alignmentGuide(.top) { $0[VerticalAlignment.center] - 9 }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.sender).font(.body.weight(message.status == .new ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 4)
                    if !message.nextSteps.isEmpty {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Has next steps")
                    }
                    if let at = message.receivedAt {
                        Text(Self.when(at)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Text(message.subject.isEmpty ? "(No subject)" : message.subject).font(.callout).lineLimit(1)
                if !message.summary.isEmpty {
                    Text(message.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(message.status == .new ? "Unread" : "")
    }

    /// "14:05" today, "Tue" this week, "12 Oct" before.
    static func when(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if let days = cal.dateComponents([.day], from: date, to: now).day, days < 6 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Labels for a mail's next steps, shared with the notch.
enum NextStepChips {
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

    /// The short button word in the reading pane; the icon beside it says where it goes.
    static func shortVerb(_ kind: MailAction.Kind) -> String {
        switch kind {
        case .event, .task: "Add"
        case .deadline: "Remind"
        case .note: "Save"
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

/// The reading pane: who wrote and when, Blink's summary, what Blink found in it (each one a click away from the
/// calendar, Reminders, tasks or notes), then the whole mail, fetched when opened and never stored.
struct MailReader: View {
    @Environment(AppModel.self) private var model
    let message: EmailMessage
    let close: () -> Void
    @State private var text: String?
    @State private var problem: String?
    @State private var writingNote = false
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !message.summary.isEmpty || !message.reason.isEmpty || !message.nextSteps.isEmpty { blinkCard }
                body(text)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                .font(.title2.weight(.semibold)).textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .center, spacing: 10) {
                Text(String(message.sender.prefix(1)).uppercased())
                    .font(.callout.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.gradient, in: .circle)
                    .accessibilityHidden(true)
                Text(message.sender).font(.headline).lineLimit(1)
                    .help(message.fromAddr)
                if Set(model.mailStates.map(\.account)).count > 1 {
                    Text(EmailMessage.accountName(message.account)).font(.caption).foregroundStyle(.secondary)
                }
                if let at = message.receivedAt {
                    Text(at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.draftingMail.contains(message.id) { ProgressView().controlSize(.small) }
                replyMenu
            }
        }
    }

    /// Reply (or Review & Send when a draft waits), with the rarer choices behind its arrow.
    @ViewBuilder
    private var replyMenu: some View {
        let more = Group {
            if !message.isNoReply { Button("Reply with a Note…") { writingNote = true } }
            if let url = message.mailURL { Button("Open in Apple Mail") { NSWorkspace.shared.open(url) } }
        }
        if message.isNoReply && message.status != .drafted {
            if let url = message.mailURL { Button("Open in Mail") { NSWorkspace.shared.open(url) }.buttonStyle(.link) }
        } else {
            let menu = Menu { more } label: { Text(message.status == .drafted ? "Review & Send" : "Reply") }
                primaryAction: { Task { await model.reviewReply(to: message) } }
                .menuStyle(.button)
                .fixedSize()
                .disabled(model.draftingMail.contains(message.id))
                .popover(isPresented: $writingNote, arrowEdge: .bottom) { notePopover }
            if message.status == .drafted { menu.buttonStyle(.borderedProminent) } else { menu }
        }
    }

    /// What Blink made of it: the summary and why it's sorted where it is, then the next steps, each one a click away.
    private var blinkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.summary.isEmpty { Text(message.summary).font(.callout) }
            if !message.reason.isEmpty { Text(message.reason).font(.caption).foregroundStyle(.secondary) }
            if !message.nextSteps.isEmpty {
                if !message.summary.isEmpty || !message.reason.isEmpty { Divider() }
                ForEach(Array(message.nextSteps.enumerated()), id: \.offset) { index, step in
                    let saved = model.savedSteps.contains("\(message.id)#\(index)")
                    HStack(spacing: 10) {
                        Image(systemName: NextStepChips.symbol(step.kind)).foregroundStyle(.secondary).frame(width: 22).accessibilityHidden(true)
                        Text(NextStepChips.text(step)).font(.callout).lineLimit(2)
                        Spacer()
                        if saved {
                            Label("Added", systemImage: "checkmark").font(.callout).foregroundStyle(.secondary)
                                .accessibilityLabel("Added: \(step.title)")
                        } else {
                            Button(NextStepChips.shortVerb(step.kind)) { Task { await model.save(step, from: message, index: index) } }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .accessibilityLabel("\(NextStepChips.verb(step.kind)): \(NextStepChips.text(step))")
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Tokens.Radius.tile)
    }

    @ViewBuilder
    private func body(_ text: String?) -> some View {
        if let text {
            Text(text.isEmpty ? AttributedString("This email has no text.") : MailText.readable(text))
                .font(.body).lineSpacing(4).textSelection(.enabled)
                .tint(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let problem {
            Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        } else {
            ProgressView("Opening…").frame(maxWidth: .infinity).padding(.top, 20)
        }
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
#endif
