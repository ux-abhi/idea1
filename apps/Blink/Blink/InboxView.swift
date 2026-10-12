// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI

/// Inbox (Phase 5): mail the server checked and sorted, by mailbox, searchable. Important first; each section folds.
/// Replies are drafted, reviewed here and sent after Touch ID, now or later.
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("inbox.account") private var account = "all"
    @State private var query = ""

    var body: some View {
        @Bindable var model = model
        let shown = model.emails.filter(matches)
        let important = shown.filter { $0.triage == .important }
        DashPage("Inbox", summary: summary(important: important.count)) {
            if accounts.count > 1 {
                Picker("Mailbox", selection: $account) {
                    Text("All").tag("all")
                    ForEach(accounts, id: \.self) { Text(EmailMessage.accountName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
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
                MailSection(key: "outbox", title: "Scheduled to send", count: scheduled.count) {
                    CardRows(items: scheduled) { OutboxRow(action: $0) }
                }
            }
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
            section("reply", "Needs a reply", shown.filter { $0.triage == .normal && $0.needsReply })
            section("rest", "Everything else", shown.filter { $0.triage == .normal && !$0.needsReply })
            section("newsletter", "Not important", shown.filter { $0.triage == .newsletter }, openByDefault: false)
        }
        .searchable(text: $query, prompt: "Search mail")
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
            MailSection(key: key, title: title, count: list.count, openByDefault: openByDefault) {
                CardRows(items: list) { MailRow(message: $0) }
            }
        }
    }

    private func summary(important: Int) -> String {
        let checked = model.mailStates.compactMap(\.lastCheckedAt).max()
        let when = checked.map { "checked \($0.formatted(.relative(presentation: .named)))" } ?? "not checked yet"
        return important == 0 ? "Nothing important · \(when)" : "\(important) important · \(when)"
    }
}

/// One foldable Inbox section; whether it's open is remembered per section.
private struct MailSection<Content: View>: View {
    let title: String
    let count: Int
    @AppStorage private var open: Bool
    @ViewBuilder let content: Content

    init(key: String, title: String, count: Int, openByDefault: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        _open = AppStorage(wrappedValue: openByDefault, "inbox.open.\(key)")
        self.content = content()
    }

    var body: some View {
        DashCard {
            DisclosureGroup(isExpanded: $open) {
                content.padding(.top, 8)
            } label: {
                Text("\(title) · \(count)").font(.headline)
            }
        }
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

/// One email: sender, subject, Blink's one-line summary and why it matters; Reply (review and send), Done, and a menu
/// to mark it important or not.
struct MailRow: View {
    @Environment(AppModel.self) private var model
    let message: EmailMessage
    @State private var writingNote = false
    @State private var note = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.triage == .important ? "exclamationmark.circle.fill" : message.status == .drafted ? "envelope.open" : "envelope")
                .foregroundStyle(message.triage == .important ? Color.red : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(message.sender).font(.headline).lineLimit(1)
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
                    Button("Done") { Task { await model.setStatus(.done, of: message) } }
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
                Task { await model.draftReply(to: message, note: note) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
    }
}
#endif
