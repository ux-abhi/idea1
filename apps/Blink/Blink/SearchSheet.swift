// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// ⌘K: find a note, task, reminder, post or space by its words, and jump to it.
struct SearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let open: (MainWindow.Page, _ noteID: String?) -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private struct Hit: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let page: MainWindow.Page
        var noteID: String?
    }

    var body: some View {
        let results = hits
        let current = min(selected, max(results.count - 1, 0))
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes, tasks, reminders, posts and spaces", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { if results.indices.contains(current) { go(results[current]) } }
                    .onKeyPress(.downArrow) { selected = min(current + 1, results.count - 1); return .handled }
                    .onKeyPress(.upArrow) { selected = max(current - 1, 0); return .handled }
                    .onChange(of: query) { selected = 0 }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Type to search. ↑↓ to move, Return to open.").foregroundStyle(.secondary).padding(14)
                        } else if results.isEmpty {
                            Text("Nothing matches “\(query)”.").foregroundStyle(.secondary).padding(14)
                        }
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                            Button { go(hit) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: hit.symbol).foregroundStyle(.secondary).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(hit.title).lineLimit(1)
                                        Text(hit.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(index == current ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 8))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .id(hit.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: current) { if results.indices.contains(current) { proxy.scrollTo(results[current].id) } }
            }
        }
        .frame(width: 560, height: 420)
        .onAppear { focused = true }
    }

    private var hits: [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        func has(_ text: String) -> Bool { text.localizedCaseInsensitiveContains(q) }
        var list: [Hit] = []
        list += model.spaces.filter { has($0.title) || has($0.goal) }
            .map { Hit(id: "s" + $0.id, symbol: $0.icon, title: $0.title, detail: "Space", page: .space($0.id)) }
        list += model.notes.filter { has($0.title) || has($0.body) }
            .map { Hit(id: "n" + $0.id, symbol: "note.text", title: $0.title.isEmpty ? "New note" : $0.title,
                       detail: "Note · " + $0.body.prefix(80).replacingOccurrences(of: "\n", with: " "), page: .section(.notes), noteID: $0.id) }
        list += model.items.filter { $0.type == .task && $0.status != .archived && has($0.title) }
            .map { Hit(id: "t" + $0.id, symbol: $0.status == .done ? "checkmark.circle.fill" : "circle", title: $0.title,
                       detail: $0.status == .done ? "Task · done" : "Task", page: $0.spaceID.map { .space($0) } ?? .section(.tasks)) }
        list += model.allReminders.filter { has($0.title) }
            .map { Hit(id: "r" + $0.id, symbol: "bell", title: $0.title, detail: "Apple Reminder", page: .section(.tasks)) }
        list += model.content.filter { has($0.body) || has($0.idea) || $0.parts.contains(where: has) }
            .map { Hit(id: "c" + $0.id, symbol: "megaphone", title: $0.hook.isEmpty ? $0.idea : $0.hook,
                       detail: "\($0.platform.name) post · \($0.status.rawValue)", page: .section(.content)) }
        return Array(list.prefix(40))
    }

    private func go(_ hit: Hit) {
        open(hit.page, hit.noteID)
        dismiss()
    }
}
#endif
