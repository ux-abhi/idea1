// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI

/// Inbox (Phase 5): mail the server checked and sorted. Important first; replies are drafted into Apple Mail, never sent.
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewsletters = false

    var body: some View {
        let important = model.emails.filter { $0.triage == .important }
        let reply = model.emails.filter { $0.triage == .normal && $0.needsReply }
        let rest = model.emails.filter { $0.triage == .normal && !$0.needsReply }
        let newsletters = model.emails.filter { $0.triage == .newsletter }
        DashPage("Inbox", summary: summary(important: important.count)) {
            if let problem = model.mailProblem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            ForEach(model.mailStates.filter { $0.lastError != nil }, id: \.account) { state in
                Label("\(state.account == "gmail" ? "Gmail" : "iCloud"): \(state.lastError ?? "")", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            if model.emails.isEmpty {
                EmptyCard(symbol: "envelope", title: model.mailStates.isEmpty ? "Mail isn't connected yet" : "Nothing new",
                          message: model.mailStates.isEmpty
                            ? "Add your Gmail and iCloud app passwords to your server's secrets (GMAIL_ADDRESS, GMAIL_APP_PASSWORD, ICLOUD_ADDRESS, ICLOUD_APP_PASSWORD), then press Check Now."
                            : "Blink checks your mail every 5 minutes. Important mail shows here and in the notch.",
                          actionTitle: "Check Now", action: { Task { await model.syncMail() } })
            }
            section("Important", important)
            section("Needs a reply", reply)
            section("Everything else", rest)
            if !newsletters.isEmpty {
                DashCard {
                    DisclosureGroup(isExpanded: $showNewsletters) {
                        CardRows(items: newsletters) { MailRow(message: $0) }.padding(.top, 8)
                    } label: {
                        Text("Newsletters and notifications (\(newsletters.count))").font(.headline)
                    }
                }
            }
        }
        .toolbar {
            Button { Task { await model.syncMail() } } label: {
                if model.syncingMail { ProgressView().controlSize(.small) } else { Label("Check Mail", systemImage: "envelope.arrow.triangle.branch") }
            }
            .disabled(model.syncingMail)
            .help("Check Gmail and iCloud now")
        }
        .task {
            await model.loadMail()
            // Seen here: the notch stops announcing these.
            for message in model.importantMail where message.status == .new { await model.setStatus(.seen, of: message) }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [EmailMessage]) -> some View {
        if !list.isEmpty {
            DashCard("\(title) · \(list.count)") { CardRows(items: list) { MailRow(message: $0) } }
        }
    }

    private func summary(important: Int) -> String {
        let checked = model.mailStates.compactMap(\.lastCheckedAt).max()
        let when = checked.map { "checked \($0.formatted(.relative(presentation: .named)))" } ?? "not checked yet"
        return important == 0 ? "Nothing important · \(when)" : "\(important) important · \(when)"
    }
}

/// One email: sender, subject, Blink's one-line summary and why it matters; Draft Reply, Open in Mail, Done.
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
                    if message.status == .drafted {
                        Label("Draft in Apple Mail", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                    } else {
                        Button {
                            Task { await model.draftReply(to: message) }
                        } label: {
                            if model.draftingMail.contains(message.id) { ProgressView().controlSize(.small) } else { Text("Draft Reply") }
                        }
                        .disabled(model.draftingMail.contains(message.id))
                        Button("With a Note…") { writingNote = true }
                            .popover(isPresented: $writingNote, arrowEdge: .bottom) { notePopover }
                    }
                    if let url = message.mailURL { Button("Open in Mail") { NSWorkspace.shared.open(url) } }
                    Button("Done") { Task { await model.setStatus(.done, of: message) } }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .contain)
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
