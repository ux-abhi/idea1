// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// /meet in the notch: a Google Meet invite that shows exactly what will be sent. Create asks for Touch ID, then the
/// owner's server creates the event with a Meet link and Google emails the guests.
struct MeetPanel: View {
    let app: AppModel
    let done: () -> Void
    /// The draft as it was when the card was drawn: shown while closing the notch clears app.meetDraft, so the fields
    /// never unwrap a nil mid-update (that crashed). Edits always go to app.meetDraft, the one copy.
    let shown: AppModel.MeetDraft
    @State private var guestInput = ""
    @State private var problem: String?
    @FocusState private var focus: Field?
    private enum Field { case title, guest }

    var body: some View {
        card(Binding(get: { app.meetDraft ?? shown }, set: { if app.meetDraft != nil { app.meetDraft = $0 } }))
    }

    private func card(_ draft: Binding<AppModel.MeetDraft>) -> some View {
        let suggestions = matches(guestInput, excluding: draft.wrappedValue.guests)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("New Google Meet", systemImage: "video").font(.headline)
                Spacer()
                if let account = app.googleAccount { Text(account).font(.caption).foregroundStyle(.white.opacity(0.45)).lineLimit(1) }
            }

            if app.googleAccount == nil {
                HStack {
                    Text("Connect Google once to create Meet invites.").foregroundStyle(.white.opacity(0.7))
                    Button("Open Settings") { done(); app.openSettings("connections") }
                }
            }

            TextField("Title", text: draft.title)
                .textFieldStyle(.plain).focused($focus, equals: .title)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 8, style: .continuous))

            HStack(spacing: 10) {
                DatePicker("When", selection: draft.start, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.compact)
                Picker("Length", selection: draft.minutes) {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                }
                .labelsHidden().fixedSize()
            }

            // Guests: chips, then a field that takes a name from your mail or any email address.
            HStack(spacing: 6) {
                ForEach(draft.wrappedValue.guests, id: \.self) { guest in
                    Button { draft.wrappedValue.guests.removeAll { $0 == guest } } label: {
                        Label(guest, systemImage: "xmark").labelStyle(.titleAndIcon).lineLimit(1)
                    }
                    .buttonStyle(.plain).font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.12), in: .capsule)
                    .accessibilityLabel("Remove \(guest)")
                }
                TextField(draft.wrappedValue.guests.isEmpty ? "Invite by name or email" : "Add more", text: $guestInput)
                    .textFieldStyle(.plain).focused($focus, equals: .guest)
                    .onSubmit { add(suggestions.first?.email ?? guestInput, to: draft) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 8, style: .continuous))

            if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.email) { person in
                        Button(person.name.isEmpty ? person.email : person.name) { add(person.email, to: draft) }
                            .buttonStyle(.plain).font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.06), in: .capsule)
                            .help(person.email)
                    }
                }
            }

            HStack {
                if let problem { Text(problem).font(.caption).foregroundStyle(.orange).lineLimit(2) }
                Spacer()
                if app.creatingMeet { ProgressView().controlSize(.small).accessibilityLabel("Creating meeting") }
                Button("Create & Invite") { create(draft.wrappedValue) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(app.creatingMeet || app.googleAccount == nil || !ready(draft.wrappedValue))
            }
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .onAppear { focus = draft.wrappedValue.title.isEmpty ? .title : .guest }
        .onExitCommand(perform: done)
        .onChange(of: problem) { if let problem { AccessibilityNotification.Announcement(problem).post() } }
    }

    private func ready(_ draft: AppModel.MeetDraft) -> Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty && !draft.guests.isEmpty && draft.start > .now.addingTimeInterval(-5 * 60)
    }

    /// People from your mail whose name or address starts with what's typed (up to four).
    private func matches(_ text: String, excluding: [String]) -> [(name: String, email: String)] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return Array(app.knownPeople.filter { person in
            !excluding.contains(person.email)
                && (person.email.hasPrefix(q) || person.name.lowercased().split(separator: " ").contains { $0.hasPrefix(q) })
        }.prefix(4))
    }

    private func add(_ text: String, to draft: Binding<AppModel.MeetDraft>) {
        let email = text.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "<>,;"))).lowercased()
        guard QuickCommand.isEmail(email) else {
            problem = guestInput.isEmpty ? nil : "Type an email address, or pick someone from the list."
            return
        }
        if !draft.wrappedValue.guests.contains(email) { draft.wrappedValue.guests.append(email) }
        guestInput = ""
        problem = nil
    }

    private func create(_ draft: AppModel.MeetDraft) {
        problem = nil
        Task {
            let failure = await app.createMeet(draft)
            if let failure { problem = failure } else if app.meetDraft == nil { done() }
        }
    }
}
#endif
