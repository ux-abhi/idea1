// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI

/// Inbox, laid out like Mail: the sorted list on the left, the open mail on the right, and the actions (Reply, Clear,
/// Teach Blink) in the toolbar for whatever is selected. The list is a native one, so arrows, Shift-click, ⌘A and the
/// Delete key work as everywhere on the Mac; E clears, R replies. A mail's next steps (an event, a deadline, a to-do,
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
            section("Waiting for your reply", reply)
            section("Everything else", rest)
            if !newsletters.isEmpty {
                Section(isExpanded: $newsletterOpen) {
                    ForEach(newsletters) { MailListRow(message: $0).tag($0.id) }
                } header: {
                    Text("Not important · \(newsletters.count)")
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
            if model.emails.isEmpty { emptyState } else if shown.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .safeAreaInset(edge: .top, spacing: 0) { banners }
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [EmailMessage]) -> some View {
        if !list.isEmpty {
            Section("\(title) · \(list.count)") {
                ForEach(list) { MailListRow(message: $0).tag($0.id) }
            }
        }
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
                if let problem = model.mailProblem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                ForEach(errors, id: \.account) { state in
                    Label("\(EmailMessage.accountName(state.account)): \(state.lastError ?? "")", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).lineLimit(2)
                }
                if let sending = model.sendingNow {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Sending “\(sending.payload.subject ?? sending.title)”…").lineLimit(1)
                        Spacer()
                        Button("Cancel") { Task { await model.cancelSend(sending) } }.controlSize(.small)
                    }
                }
                ForEach(scheduled) { action in
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(action.payload.subject ?? action.title).lineLimit(1)
                        Spacer()
                        if let at = action.payload.sendAt {
                            Text(at, format: .dateTime.weekday(.abbreviated).hour().minute()).foregroundStyle(.secondary)
                        }
                        Button("Cancel") { Task { await model.cancelSend(action) } }.controlSize(.small)
                    }
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
                                   description: Text("Pick a mail to read it here, with what Blink found in it."))
        case 1:
            MailReader(message: picked[0], close: { selection = [] })
        default:
            ContentUnavailableView {
                Label("\(picked.count) mails selected", systemImage: "tray.full")
            } actions: {
                Button("Clear All") { clear(selection) }.buttonStyle(.borderedProminent)
                Menu("Teach Blink") { teachItems(picked) }.fixedSize()
            }
        }
    }

    // MARK: Actions

    @ToolbarContentBuilder
    private func toolbar(_ picked: [EmailMessage]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
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
            Button { clear(selection) } label: { Label("Clear", systemImage: "checkmark.circle") }
                .disabled(picked.isEmpty)
                .help("Clear from Blink's inbox (E). Anything you added from it stays.")
            Menu { teachItems(picked) } label: { Label("Teach Blink", systemImage: "graduationcap") }
                .disabled(picked.isEmpty)
                .help("Mark the sender important or not")
            Button { Task { await model.syncMail() } } label: {
                if model.syncingMail { ProgressView().controlSize(.small) } else { Label("Check Mail", systemImage: "envelope.arrow.triangle.branch") }
            }
            .disabled(model.syncingMail)
            .help("Check all your mailboxes now")
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
        Button("Clear") { clear(ids) }
        teachItems(picked)
    }

    @ViewBuilder
    private func teachItems(_ picked: [EmailMessage]) -> some View {
        Button("Mark Important", systemImage: "exclamationmark.circle") { teach(.important, picked) }
        Button("Not Important", systemImage: "arrow.down.circle") { teach(.newsletter, picked) }
        Text("Applies to all mail from \(picked.count == 1 ? picked[0].fromAddr : "these senders")")
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

/// One mail in the list: who, when, the subject, Blink's one-line summary, and small marks for "important" and for
/// next steps found. Unread mail shows a dot and a bolder sender, like Mail.
private struct MailListRow: View {
    let message: EmailMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(message.status == .new ? Color.accentColor : .clear)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.sender).font(.body.weight(message.status == .new ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 4)
                    if let at = message.receivedAt {
                        Text(Self.when(at)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Text(message.subject.isEmpty ? "(No subject)" : message.subject).font(.callout).lineLimit(1)
                Text(message.reason.isEmpty ? message.summary : message.reason)
                    .font(.callout).foregroundStyle(message.reason.isEmpty ? Color.secondary : Color.red).lineLimit(1)
                if !message.nextSteps.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(message.nextSteps.enumerated()), id: \.offset) { _, step in
                            Image(systemName: NextStepChips.symbol(step.kind)).accessibilityHidden(true)
                        }
                        Text(message.nextSteps.count == 1 ? NextStepChips.text(message.nextSteps[0]) : "\(message.nextSteps.count) next steps")
                            .lineLimit(1)
                    }
                    .font(.caption).foregroundStyle(.blue)
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
                if !message.summary.isEmpty {
                    Label { Text(message.summary) } icon: { Image(systemName: "sparkles").foregroundStyle(.blue) }
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08), in: .rect(cornerRadius: Tokens.Radius.tile - 6, style: .continuous))
                }
                if !message.nextSteps.isEmpty { nextSteps }
                Divider()
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
        VStack(alignment: .leading, spacing: 10) {
            Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                .font(.title2.weight(.semibold)).textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .center, spacing: 10) {
                Text(String(message.sender.prefix(1)).uppercased())
                    .font(.headline).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.gradient, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.sender).font(.headline)
                    Text("\(message.fromAddr) · \(EmailMessage.accountName(message.account))").font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                if let at = message.receivedAt {
                    Text(at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                // Replying only where someone reads it; the blue button only when someone is waiting for you.
                if !message.isNoReply || message.status == .drafted {
                    if message.needsReply || message.status == .drafted {
                        Button(message.status == .drafted ? "Review & Send" : "Reply") { Task { await model.reviewReply(to: message) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.draftingMail.contains(message.id))
                    } else {
                        Button("Reply") { Task { await model.reviewReply(to: message) } }
                            .disabled(model.draftingMail.contains(message.id))
                    }
                    Button("Reply with a Note…") { writingNote = true }
                        .popover(isPresented: $writingNote, arrowEdge: .bottom) { notePopover }
                }
                if model.draftingMail.contains(message.id) { ProgressView().controlSize(.small) }
                Spacer()
                if let url = message.mailURL { Button("Open in Mail") { NSWorkspace.shared.open(url) }.buttonStyle(.link) }
            }
            .controlSize(.regular)
        }
    }

    private var nextSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blink found").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(message.nextSteps.enumerated()), id: \.offset) { index, step in
                    let saved = model.savedSteps.contains("\(message.id)#\(index)")
                    if index > 0 { Divider() }
                    HStack(spacing: 10) {
                        Image(systemName: NextStepChips.symbol(step.kind)).foregroundStyle(.blue).frame(width: 22).accessibilityHidden(true)
                        Text(NextStepChips.text(step)).lineLimit(2)
                        Spacer()
                        Button(saved ? "Added" : NextStepChips.verb(step.kind)) { Task { await model.save(step, from: message, index: index) } }
                            .disabled(saved)
                            .accessibilityLabel(saved ? "Added: \(step.title)" : "\(NextStepChips.verb(step.kind)): \(NextStepChips.text(step))")
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Tokens.Radius.tile - 6, style: .continuous))
        }
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
