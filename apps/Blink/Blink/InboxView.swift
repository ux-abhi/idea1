// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI

/// Inbox, laid out like a modern mail app: a page header (title, search, Bulk Mail), the list on the left (a segmented
/// filter, then compact rows with hover actions), the open mail on the right on a bright reading pane. The list is a native one, so arrows, Shift-click, ⌘A and the Delete key work as everywhere on the
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
    @AppStorage("inbox.bulk") private var bulk = false

    var body: some View {
        if bulk { BulkMailView { bulk = false } } else { inbox }
    }

    @ViewBuilder
    private var inbox: some View {
        @Bindable var model = model
        let shown = model.emails.filter(matches)
        let picked = shown.filter { selection.contains($0.id) }
        // A plain row, not an HSplitView: a second AppKit split inside the window's split view and inspector made them
        // re-measure each other in full screen until AppKit crashed ("Update Constraints in Window", on opening Inbox).
        // shortcut: the list has a fixed width; make it draggable again only with a split that doesn't loop.
        VStack(spacing: 0) {
            header(shown)
            Divider()
            HStack(spacing: 0) {
                list(shown)
                    .frame(minWidth: 260, idealWidth: 350, maxWidth: 390) // the reading pane gets the rest, even in a narrow window
                Divider()
                reader(picked)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
            HStack(spacing: 8) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { option in Text(option == .low ? "Low" : option.rawValue).tag(option) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .help(Filter.allCases.map { "\($0.rawValue): \(shown.filter(inFilter($0)).count)" }.joined(separator: " · "))
                Menu {
                    if accounts.count > 1 {
                        Picker("Mailbox", selection: $account) {
                            Text("All Mailboxes").tag("all")
                            ForEach(accounts, id: \.self) { Text(EmailMessage.accountName($0)).tag($0) }
                        }
                    }
                    Button("Check Mail Now", systemImage: "arrow.clockwise") { Task { await model.syncMail() } }
                    Button("Mail Settings…", systemImage: "gearshape") { model.openSettings("connections") }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .padding(6).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7))
                    .accessibilityLabel("Inbox options")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            banners
            List(selection: $selection) {
                ForEach(rows) { message in
                    MailListRow(message: message, reply: { Task { await model.reviewReply(to: message) } }, done: { clear([message.id]) })
                        .tag(message.id)
                        .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
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

    /// The page's own header: the title and count, then search, the mailbox's bulk mail and the primary action.
    private func header(_ shown: [EmailMessage]) -> some View {
        HStack(spacing: 12) {
            Text("Inbox").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("\(shown.filter(inFilter(.inbox)).count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            // The window toolbar stays the same on every page: items that come and go between pages crash AppKit's toolbar.
            PageSearchField(prompt: "Search mail", text: $query).frame(width: 240)
            Button { bulk = true } label: {
                Label("Bulk Mail", systemImage: "envelope.stack").foregroundStyle(Color(nsColor: .windowBackgroundColor)) // readable on the dark (or, in dark mode, light) fill
            }
                .buttonStyle(.borderedProminent).tint(.primary)
                .help("Bulk Mail: a personal mail to many people at once")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func inFilter(_ filter: Filter) -> (EmailMessage) -> Bool { { inFilter($0, filter) } }

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

/// One mail in the list: a small avatar, sender and time, the subject, one line of Blink's summary, and small tags for
/// what matters. Unread mail has a dot; hovering shows Done, Reply and more in place of the time.
private struct MailListRow: View {
    let message: EmailMessage
    let reply: () -> Void
    let done: () -> Void
    @State private var hovering = false

    var body: some View {
        let unread = message.status == .new
        HStack(alignment: .top, spacing: 10) {
            SenderAvatar(name: message.sender, key: message.senderKey, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.sender).font(.caption.weight(unread ? .semibold : .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    if hovering {
                        HStack(spacing: 8) {
                            Button("Done", systemImage: "archivebox", action: done).help("Done (E)")
                            if !message.isNoReply { Button("Reply", systemImage: "arrowshape.turn.up.left", action: reply).help("Reply (R)") }
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).font(.caption)
                    } else if let at = message.receivedAt {
                        Text(Self.when(at)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                        .font(.callout.weight(unread ? .semibold : .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    if unread { Circle().fill(Color.accentColor).frame(width: 7, height: 7).accessibilityHidden(true) }
                }
                if !message.summary.isEmpty {
                    Text(message.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .contentShape(.rect)
        .onHover { hovering = $0 }
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

/// The reading pane: who wrote and when with the actions as small icons, then the subject big, what Blink made of it
/// (summary, why, next steps a click away), then the whole mail, fetched when opened and never stored.
struct MailReader: View {
    @Environment(AppModel.self) private var model
    @State private var retries = 0
    let message: EmailMessage
    let done: () -> Void
    let teach: (SenderVerdict) -> Void
    @State private var text: String?
    @State private var problem: String?
    @State private var writingNote = false
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            senderBar
            Divider().padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                        .font(.title2.weight(.semibold)).textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    if !message.summary.isEmpty || !message.reason.isEmpty || !message.nextSteps.isEmpty { blinkCard }
                    body(text)
                }
                .padding(.horizontal, 28).padding(.vertical, 22)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: "\(message.id)#\(retries)") {
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
        if message.status == .drafted { reply.labelStyle(.titleAndIcon).buttonStyle(.borderedProminent) } else { reply.menuIndicator(.hidden) }
    }

    /// Who wrote, to which of your addresses, and when, with the mail's actions as small icons on the right.
    private var senderBar: some View {
        HStack(spacing: 10) {
            SenderAvatar(name: message.sender, key: message.senderKey, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.sender).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(message.fromAddr).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                }
                Text("To: \(EmailMessage.accountName(message.account))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if model.draftingMail.contains(message.id) { ProgressView().controlSize(.small) }
            if let at = message.receivedAt {
                Text(at.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if !message.isNoReply || message.status == .drafted { replyButton }
                Button("Done", systemImage: "archivebox", action: done)
                    .help("Done: off Blink's inbox (E). Anything you added from it stays.")
                if let url = message.mailURL {
                    Button("Open in Apple Mail", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }.help("Open in Apple Mail")
                }
                Menu {
                    Section("All mail from \(message.fromAddr)") {
                        Button("Always Important", systemImage: "exclamationmark.circle") { teach(.important) }
                        Button("Never Important", systemImage: "arrow.down.circle") { teach(.newsletter) }
                    }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("More")
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
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
            HStack {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Try Again") { retries += 1 }
            }
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
