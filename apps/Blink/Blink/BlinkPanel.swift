// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// The Blink panel (DESIGN.md: on every screen, aware of it): Blink's eyes, what waits for your OK, suggestions for
/// this page, and the same chat as the notch.
struct BlinkPanel: View {
    @Environment(AppModel.self) private var model
    let page: MainWindow.Page
    @State private var text = ""

    /// A chip: the words on it, what Blink is asked, and what's on screen (sent as data, not as part of the request).
    private struct Suggestion: Hashable {
        let title: String
        let message: String
        let context: String?
        init(_ title: String, _ message: String? = nil, context: String? = nil) {
            self.title = title
            self.message = message ?? title
            self.context = context
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let action = model.pending.first {
                            CardView(action: action, count: model.pending.count, problem: model.actionProblem, app: model)
                                .padding(12)
                                .background(.black, in: .rect(cornerRadius: 16, style: .continuous))
                                .environment(\.colorScheme, .dark)
                        }
                        if model.chat.isEmpty {
                            Text("For this page").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button { send(suggestion.message, context: suggestion.context) } label: {
                                    Label(suggestion.title, systemImage: "sparkle")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12).padding(.vertical, 9)
                                        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .disabled(model.thinking)
                            }
                        }
                        ForEach(model.chat.suffix(12)) { turn in
                            if turn.role == .user {
                                Text(turn.text)
                                    .lineLimit(4)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 12, style: .continuous))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                Text(ChatPanel.markdown(turn.text)).textSelection(.enabled)
                            }
                        }
                        if model.thinking {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(.secondary) }
                                .id("thinking")
                        }
                        if !model.quickReplies.isEmpty && !model.thinking {
                            HStack {
                                ForEach(model.quickReplies, id: \.self) { reply in
                                    Button(reply) { Task { await model.quickReply(reply) } }
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(14)
                }
                .onChange(of: model.chat.count) { proxy.scrollTo("end", anchor: .bottom) }
            }
            if model.aiKeyMissing, let step = model.setupSteps.first(where: { $0.id == .aiKey }) {
                NeedsSetup(step: step, model: model).padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask Blink…", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit { send(text) }
                Button { send(text) } label: { Image(systemName: "arrow.up.circle.fill").imageScale(.large) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || model.thinking)
                    .accessibilityLabel("Send")
            }
            .padding(12)
        }
        .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
    }

    private var header: some View {
        HStack(spacing: 10) {
            BlinkEyes(mood: model.thinking ? .thinking : model.undoChip != nil ? .done : model.pending.isEmpty ? .idle : .concerned)
                .frame(width: 58, height: 32)
                .background(.black, in: .rect(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Blink").font(.headline)
                Text(model.thinking ? "Thinking…" : model.pending.isEmpty ? "Here to help" : "\(model.pending.count) waiting for you")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ModelMenu(feature: "chat", compact: true)
                .menuStyle(.borderlessButton)
                .controlSize(.small)
            if !model.chat.isEmpty {
                Button { model.clearChat() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.borderless)
                    .help("New conversation")
                    .accessibilityLabel("New conversation")
            }
        }
        .padding(12)
    }

    private func send(_ message: String, context: String? = nil) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !model.thinking else { return }
        text = ""
        // The server takes at most 2000 characters (functions/chat input.ts).
        Task { await model.ask(String(trimmed.prefix(1990)), context: context) }
    }

    /// What Blink can help with on this page. Anything it would change still comes back as an Ask-First card.
    private var suggestions: [Suggestion] {
        switch page {
        case .section(.today):
            return [Suggestion("What's left today?"), Suggestion("Plan the rest of my day"),
                    Suggestion("Move what I can't finish today",
                               "Which of today's tasks and reminders should move to tomorrow? Ask me before changing anything.")]
        case .section(.inbox):
            // The mail Blink already summarised, as data (the chat never reads mailboxes itself).
            let mail = model.emails.filter { $0.triage != .newsletter }.prefix(25)
                .map { "- \($0.sender): \($0.subject) — \($0.summary)\($0.needsReply ? " [needs reply]" : "")\($0.triage == .important ? " [important: \($0.reason)]" : "")" }
                .joined(separator: "\n")
            let context = "Recent email (sender: subject — summary):\n\(mail.isEmpty ? "none" : String(mail.prefix(3800)))"
            return [Suggestion("What needs my answer today?", "Which of these emails need my answer today, and what should I say? Keep it short.", context: context),
                    Suggestion("Anything urgent in my mail?", "Is anything in this mail urgent? One line each.", context: context)]
        case .section(.calendar):
            return [Suggestion("When am I free this week?"), Suggestion("Get me ready for my next meeting")]
        case .section(.notes):
            guard let id = model.openNoteID, let note = model.notes.first(where: { $0.id == id }), !note.body.isEmpty else {
                return [Suggestion("Help me start a note", "Help me start a note. Ask me what it's about first.")]
            }
            let context = "Open note “\(note.title)”:\n\(note.body.prefix(3500))"
            return [Suggestion("Turn this note into tasks", "Turn the open note into tasks. Ask me before adding them.", context: context),
                    Suggestion("What should I do next from this note?", "What should I do next based on the open note?", context: context)]
        case .section(.tasks):
            return [Suggestion("What should I do first?"), Suggestion("Plan my week"),
                    Suggestion("Clean up overdue tasks", "Look at my overdue tasks and reminders and suggest what to move or drop. Ask me first.")]
        case .section(.content):
            return [Suggestion("Give me 5 post ideas from my week",
                               "Give me 5 post ideas from my calendar, tasks and notes this week. One line each, in my words."),
                    Suggestion("What should I post about today?")]
        case .section(.money):
            // This month's numbers, as data: the chat never reads the table itself.
            let month = MoneyMath.month(of: HabitDay.key(.now))
            let totals = MoneyMath.totals(model.spends, month: month).map { row in
                let limit = model.budgets.first { $0.category == row.category }.map { " (limit \($0.monthlyLimit.formatted(.currency(code: "EUR"))))" } ?? ""
                return "- \(row.category.title): \(row.total.formatted(.currency(code: "EUR")))\(limit)"
            }.joined(separator: "\n")
            let recent = model.spends.filter { MoneyMath.month(of: $0.spentOn) == month }.prefix(40).map { "- \($0.spentOn) \($0.note) \($0.amount.formatted(.currency(code: "EUR"))) [\($0.category.title)]" }
                .joined(separator: "\n")
            let summary = MoneyMath.summary(model.spends, today: HabitDay.key(.now))
            let balance = MoneyMath.totalBalance(model.accounts)
            let accounts = model.accounts.map { "- \($0.name) (\($0.kind.title)): \(MoneyMath.balance(of: $0).formatted(.currency(code: "EUR")))" }
                .joined(separator: "\n")
            let money = model.accounts.isEmpty ? "Accounts: none added yet.\n"
                : "Accounts now:\n\(accounts)\nTotal: \(balance.formatted(.currency(code: "EUR"))). Left at month end at this pace: \(MoneyMath.leftAtMonthEnd(total: balance, summary: summary, today: HabitDay.key(.now)).formatted(.currency(code: "EUR"))).\n"
            let context = String("\(money)Spent this month: \(summary.total.formatted(.currency(code: "EUR"))), \(summary.average.formatted(.currency(code: "EUR"))) a day, last month \(summary.lastMonthTotal.formatted(.currency(code: "EUR"))).\nBy category:\n\(totals.isEmpty ? "none" : totals)\nLatest spends:\n\(recent.isEmpty ? "none" : recent)".prefix(3900))
            return [Suggestion("How am I doing this month?", "How am I doing with money this month, given my balances and spending? Three short lines.", context: context),
                    Suggestion("Where is my money going?", "Where is my money going this month? Two or three short lines.", context: context),
                    Suggestion("Can I afford something?", "I'm thinking of buying something. Ask me what and how much, then tell me if my balances and pace allow it.", context: context),
                    Suggestion("How can I spend less?", "Based on this month, where could I spend less? Concrete, short.", context: context)]
        case .section(.waiting):
            return [Suggestion("Explain what's waiting for me")]
        case .section(.activity):
            return [Suggestion("What did you do for me today?")]
        case .space(let id):
            guard let space = model.spaces.first(where: { $0.id == id }) else { return [] }
            let open = model.openTasks.filter { $0.spaceID == id }.prefix(20).map { "- \($0.title)" }.joined(separator: "\n")
            let context = "Space “\(space.title)”. Goal: \(space.goal.isEmpty ? "not set" : space.goal)."
                + (space.dueAt.map { " Due \($0.formatted(date: .abbreviated, time: .omitted))." } ?? "")
                + "\nOpen tasks:\n\(open.isEmpty ? "none yet" : open)"
            return [Suggestion("Plan the next steps", "Plan the next steps for this space. Ask me before adding tasks.", context: context),
                    Suggestion("What's at risk?", "What's at risk of slipping in this space, and what should I do about it?", context: context)]
        }
    }
}
#endif
