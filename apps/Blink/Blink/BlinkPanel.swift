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
