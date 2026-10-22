// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI

/// Inbox, laid out like a modern mail app: the list on the left (filter pills on top, then mail with an avatar, sender
/// and time, subject, a two-line summary and small tags), the open mail on the right on a bright reading pane with its
/// own action bar. The list is a native one, so arrows, Shift-click, ⌘A and the Delete key work as everywhere on the
/// Mac; E marks done, R replies.
struct InboxView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case inbox = "All", important = "Important", reply = "To Reply", low = "Low Priority"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @AppStorage("inbox.account") private var account = "all"
    @AppStorage("inbox.filter") private var filter = Filter.inbox
    @State private var query = ""
    @State private var selection: Set<String> = []

    var body: some View {
        @Bindable var model = model
        let shown = model.emails.filter(matches)
        let picked = shown.filter { selection.contains($0.id) }
        HSplitView {
            list(shown)
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 520)
            reader(picked)
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search mail")
        .sheet(item: $model.reviewing) { ReplyReviewSheet(review: $0) }
        .task {
            await model.loadMail()
            // Seen here: the notch stops announcing these.
            for message in model.importantMail where message.status == .new { await model.setStatus(.seen, of: message) }
        }
        .onChange(of: model.emails) { _, emails in selection.formIntersection(emails.map(\.id)) }
        .onChange(of: filter) { selection = [] } // never act on mail the list no longer shows
    }

    // MARK: The list

    private func inFilter(_ message: EmailMessage, _ filter: Filter) -> Bool {
        switch filter {
        case .inbox: message.triage != .newsletter
        case .important: message.triage == .important
        case .reply: message.triage != .newsletter && message.needsReply
        case .low: message.triage == .newsletter
        }
    }

    private func list(_ shown: [EmailMessage]) -> some View {
        // Important first, then the rest, each newest first (the server's order).
        let rows = shown.filter { inFilter($0, filter) }.sorted { ($0.triage == .important ? 0 : 1) < ($1.triage == .important ? 0 : 1) }
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Inbox").font(.system(.title, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
                    Text("\(shown.filter { inFilter($0, .inbox) }.count) emails").foregroundStyle(.secondary)
                    Spacer()
                    if accounts.count > 1 {
                        Picker("Mailbox", selection: $account) {
                            Text("All Mailboxes").tag("all")
                            ForEach(accounts, id: \.self) { Text(EmailMessage.accountName($0)).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Filter.allCases) { option in
                            FilterPill(title: option.rawValue, count: shown.filter { inFilter($0, option) }.count, on: filter == option) {
                                filter = option
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            banners
            List(selection: $selection) {
                ForEach(rows) { message in
                    MailListRow(message: message)
                        .tag(message.id)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .accessibilityAction(named: "Reply") { Task { await model.reviewReply(to: message) } }
                        .accessibilityAction(named: "Done") { clear([message.id]) }
                }
            }
            .listStyle(.plain)
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
                } else if rows.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView(filter == .inbox ? "No mail here" : "Nothing in \(filter.rawValue)", systemImage: "tray")
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                                   description: Text("Blink checks your mail every 5 minutes."))
        }
    }

    /// Problems, a send in progress and scheduled mail: one thin line each, only when there's something.
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5))
        }
    }

    // MARK: Reading pane

    @ViewBuilder
    private func reader(_ picked: [EmailMessage]) -> some View {
        switch picked.count {
        case 0:
            ContentUnavailableView("No mail selected", systemImage: "envelope.open", description: Text("Select a mail to read it."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        case 1:
            MailReader(message: picked[0], done: { clear([picked[0].id]) }, teach: { teach($0, [picked[0]]) })
        default:
            ContentUnavailableView {
                Label("\(picked.count) mails selected", systemImage: "tray.full")
            } actions: {
                Button("Mark All Done") { clear(selection) }.buttonStyle(.borderedProminent)
                Menu("Sender") { teachItems(picked) }.fixedSize()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: Actions

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

/// A round initial in a colour of its own for each sender, so the list is easy to scan.
struct SenderAvatar: View {
    let name: String
    let key: String
    var size = 36.0

    private static let colors: [Color] = [.blue, .orange, .green, .pink, .teal, .indigo, .red, .purple, .brown]

    var body: some View {
        let index = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % Self.colors.count
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.colors[index].gradient, in: .circle)
            .accessibilityHidden(true)
    }
}

/// One mail in the list: avatar, sender and time, the subject, Blink's summary on two lines, and small tags for what
/// matters. Unread mail has a bolder sender and a dot.
private struct MailListRow: View {
    let message: EmailMessage

    var body: some View {
        let unread = message.status == .new
        HStack(alignment: .top, spacing: 12) {
            SenderAvatar(name: message.sender, key: message.senderKey)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.sender).font(.callout.weight(unread ? .bold : .semibold)).lineLimit(1)
                    if unread { Circle().fill(Color.accentColor).frame(width: 7, height: 7).accessibilityHidden(true) }
                    Spacer(minLength: 4)
                    if let at = message.receivedAt {
                        Text(Self.when(at)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                    .font(.callout.weight(unread ? .semibold : .regular)).lineLimit(1)
                if !message.summary.isEmpty {
                    Text(message.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if message.triage == .important || message.needsReply || !message.nextSteps.isEmpty {
                    HStack(spacing: 5) {
                        if message.triage == .important { Tag(text: "Important", tint: .red) }
                        if message.needsReply { Tag(text: "Reply", tint: .blue) }
                        if !message.nextSteps.isEmpty {
                            Tag(text: message.nextSteps.count == 1 ? "1 next step" : "\(message.nextSteps.count) next steps", tint: .teal)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread ? "Unread" : "")
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

/// The reading pane: an action bar (Reply, Done, Sender, Open in Mail), then the subject big, who wrote and when,
/// what Blink made of it (summary, why, next steps a click away), then the whole mail, fetched when opened and never
/// stored.
struct MailReader: View {
    @Environment(AppModel.self) private var model
    let message: EmailMessage
    let done: () -> Void
    let teach: (SenderVerdict) -> Void
    @State private var text: String?
    @State private var problem: String?
    @State private var writingNote = false
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                        .font(.system(.title, weight: .bold)).textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 12) {
                        SenderAvatar(name: message.sender, key: message.senderKey, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.sender).font(.headline).lineLimit(1)
                            Text(message.fromAddr).font(.callout).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if let at = message.receivedAt {
                                Text(at.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
                            }
                            if Set(model.mailStates.map(\.account)).count > 1 {
                                Text(EmailMessage.accountName(message.account)).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if !message.summary.isEmpty || !message.reason.isEmpty || !message.nextSteps.isEmpty { blinkCard }
                    body(text)
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
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

    @ViewBuilder
    private var replyButton: some View {
        let reply = Menu {
            if !message.isNoReply { Button("Reply with a Note…") { writingNote = true } }
        } label: {
            Label(message.status == .drafted ? "Review & Send" : "Reply", systemImage: "arrowshape.turn.up.left")
        } primaryAction: {
            Task { await model.reviewReply(to: message) }
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(model.draftingMail.contains(message.id))
        .popover(isPresented: $writingNote, arrowEdge: .bottom) { notePopover }
        .help("Reply (R)")
        if message.status == .drafted { reply.buttonStyle(.borderedProminent) } else { reply }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            if !message.isNoReply || message.status == .drafted { replyButton }
            Button(action: done) { Label("Done", systemImage: "archivebox") }
                .help("Done: off Blink's inbox (E). Anything you added from it stays.")
            Menu {
                Section("All mail from \(message.fromAddr)") {
                    Button("Always Important", systemImage: "exclamationmark.circle") { teach(.important) }
                    Button("Never Important", systemImage: "arrow.down.circle") { teach(.newsletter) }
                }
            } label: {
                Label("Sender", systemImage: "person.crop.circle")
            }
            .fixedSize()
            if model.draftingMail.contains(message.id) { ProgressView().controlSize(.small) }
            Spacer()
            if let url = message.mailURL {
                Button { NSWorkspace.shared.open(url) } label: { Label("Open in Mail", systemImage: "arrow.up.forward.app") }
                    .labelStyle(.iconOnly)
                    .help("Open in Apple Mail")
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// What Blink made of it: the summary and why it's sorted where it is, then the next steps, each one a click away.
    private var blinkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Blink", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if !message.summary.isEmpty { Text(message.summary).font(.callout) }
            if !message.reason.isEmpty { Text(message.reason).font(.caption).foregroundStyle(.secondary) }
            if !message.nextSteps.isEmpty {
                Divider()
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
                            Button(NextStepChips.verb(step.kind)) { Task { await model.save(step, from: message, index: index) } }
                                .controlSize(.small)
                                .accessibilityLabel("\(NextStepChips.verb(step.kind)): \(NextStepChips.text(step))")
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: Tokens.Radius.tile, style: .continuous))
    }

    @ViewBuilder
    private func body(_ text: String?) -> some View {
        if let text {
            Text(text.isEmpty ? AttributedString("This email has no text.") : MailText.readable(text))
                .font(.body).lineSpacing(5).textSelection(.enabled)
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
