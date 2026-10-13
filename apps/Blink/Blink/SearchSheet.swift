// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// ⌘K: find a note, task, reminder, post or space by its words, and jump to it (the notch has the same, ⌃⌥K).
struct SearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let open: (MainWindow.Page, _ noteID: String?) -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = model.search(query)
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

    private func go(_ hit: AppModel.SearchHit) {
        open(MainWindow.Page(key: hit.pageKey), hit.noteID)
        dismiss()
    }
}
#endif
