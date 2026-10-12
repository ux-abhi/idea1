// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI

/// Content: one idea → a draft per platform (§36.4). Edit, approve, then copy & open to post it yourself.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var idea = ""
    @AppStorage("contentPlatforms") private var picked = "instagram,linkedin,x"
    @State private var editingVoice = false
    @State private var showPosted = false

    var body: some View {
        let live = model.content.filter { $0.status != .published }
        let posted = model.content.filter { $0.status == .published }
        let ready = live.filter { $0.status == .approved }.count
        DashPage("Content", summary: live.isEmpty ? "Ideas into posts" : "\(live.count) drafts · \(ready) ready to post") {
            DashCard("New post") {
                TextField("What's the idea? e.g. \"3 checkout mistakes that lose users\". Or leave it empty and ask for ideas.", text: $idea, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...6)
                    .padding(10)
                    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
                HStack(spacing: 8) {
                    ForEach(ContentPiece.Platform.allCases, id: \.self) { platform in
                        let on = platforms.contains(platform)
                        Button { toggle(platform) } label: {
                            Label(platform.name, systemImage: on ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? .accentColor : .secondary)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    Spacer()
                    ModelMenu(feature: "content", compact: true)
                        .menuStyle(.borderlessButton)
                        .controlSize(.small)
                    Button {
                        Task { await model.planWeek(theme: idea, platforms: platforms) }
                    } label: { Label("Plan My Week", systemImage: "calendar") }
                    .disabled(platforms.isEmpty || model.thinkingOfIdeas)
                    Button {
                        Task { await model.suggestIdeas(theme: idea, platforms: platforms) }
                    } label: {
                        if model.thinkingOfIdeas { ProgressView().controlSize(.small) } else { Label("Give Me Ideas", systemImage: "lightbulb") }
                    }
                    .disabled(platforms.isEmpty || model.thinkingOfIdeas)
                    Button {
                        Task { if await model.draft(idea: idea, platforms: platforms) { idea = "" } }
                    } label: {
                        if model.drafting { ProgressView().controlSize(.small) } else { Label("Write Drafts", systemImage: "sparkles") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || platforms.isEmpty || model.drafting)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                if let problem = model.contentProblem {
                    Text(problem).font(.callout).foregroundStyle(.orange)
                } else if !model.voice.isSetUp {
                    Button("Tell Blink about your page (e.g. @uxabhi, who it's for, your topics) so posts aren't generic…") { editingVoice = true }
                        .buttonStyle(.link)
                }
            }

            if !model.weekPlan.isEmpty {
                DashCard("Your week", trailing: "Clear", action: { model.clearWeekPlan() }) {
                    CardRows(items: model.weekPlan) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Text(HabitDay.label(item.day ?? "")).font(.callout.weight(.semibold)).frame(width: 90, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(item.platform.name) · \(item.formatName)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(item.title).font(.headline)
                                Text("“\(item.hook)”").font(.callout)
                            }
                            Spacer()
                            Button("Write") { Task { await model.write(item) } }
                                .disabled(model.drafting)
                        }
                    }
                    Button { Task { await model.writeWeek() } } label: {
                        Label("Write All \(model.weekPlan.count)", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.drafting)
                }
            }

            if !model.ideas.isEmpty {
                DashCard("Ideas", trailing: "Clear", action: { Task { await model.clearIdeas() } }) {
                    CardRows(items: model.ideas) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(item.platform.name) · \(item.formatName)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(item.title).font(.headline)
                                Text("“\(item.hook)”").font(.callout)
                                Text(item.why).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Write This") { Task { await model.write(item) } }
                                .disabled(model.drafting)
                        }
                    }
                }
            }

            if live.isEmpty && !model.drafting {
                EmptyCard(symbol: "megaphone", title: "No drafts yet",
                          message: "Write an idea above. Blink drafts an Instagram carousel or reel, a LinkedIn post and an X post or thread, checks them for AI-sounding phrases and limits, and you post them yourself.")
            }

            // One card per idea, newest first.
            ForEach(ideas(live), id: \.self) { group in
                DashCard(group) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(live.filter { $0.idea == group }) { piece in
                            PieceEditor(piece: piece)
                            if piece.id != live.last(where: { $0.idea == group })?.id { Divider() }
                        }
                    }
                }
            }

            if !posted.isEmpty {
                DashCard {
                    DisclosureGroup(isExpanded: $showPosted) {
                        CardRows(items: posted) { piece in
                            HStack {
                                Text(piece.platform.name).font(.caption.weight(.semibold)).frame(width: 70, alignment: .leading)
                                Text(piece.hook.isEmpty ? piece.body : piece.hook).lineLimit(1)
                                Spacer()
                                if let at = piece.publishedAt {
                                    Text(at, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Posted (\(posted.count))").font(.headline)
                    }
                }
            }
        }
        .toolbar {
            Button { editingVoice = true } label: { Label("Voice", systemImage: "person.wave.2") }
                .help("How you write")
        }
        .sheet(isPresented: $editingVoice) { VoiceSheet() }
        .task { await model.loadContent() }
    }

    private var platforms: [ContentPiece.Platform] {
        picked.split(separator: ",").compactMap { ContentPiece.Platform(rawValue: String($0)) }
    }

    private func toggle(_ platform: ContentPiece.Platform) {
        var set = Set(platforms)
        if set.contains(platform) { set.remove(platform) } else { set.insert(platform) }
        picked = ContentPiece.Platform.allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
    }

    /// Ideas in the order their newest draft appeared.
    private func ideas(_ pieces: [ContentPiece]) -> [String] {
        var seen = Set<String>()
        return pieces.compactMap { seen.insert($0.idea).inserted ? $0.idea : nil }
    }
}

/// One draft: the text (and its slides, posts or shots), the writing check, and Approve → Copy & Open.
private struct PieceEditor: View {
    @Environment(AppModel.self) private var model
    let piece: ContentPiece

    var body: some View {
        let check = ContentLint.check(piece, neverSay: model.voice.neverSay)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(piece.platform.name).font(.headline)
                Text(formatName).font(.caption).foregroundStyle(.secondary)
                if let day = piece.plannedFor {
                    Label(HabitDay.label(day), systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(day == HabitDay.key(.now) ? Color.orange : .secondary)
                }
                Spacer()
                ScoreBadge(score: check.score)
                Menu {
                    Button("Archive", role: .destructive) { Task { await model.setStatus(.archived, of: piece) } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("More")
            }

            if !piece.parts.isEmpty {
                ForEach(piece.parts.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(partLabel(index)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                        TextField("", text: partBinding(index), axis: .vertical).textFieldStyle(.plain)
                        if piece.platform == .x {
                            Text("\(280 - piece.parts[index].count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(piece.parts[index].count > 280 ? .red : .secondary)
                        }
                    }
                }
                Text(piece.platform == .instagram ? "Caption" : "Post").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if piece.platform != .x || piece.parts.isEmpty {
                TextEditor(text: bodyBinding)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90, maxHeight: 260)
                    .padding(6)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10, style: .continuous))
            }
            if !piece.hashtags.isEmpty {
                Text(piece.hashtags.map { "#\($0)" }.joined(separator: " ")).font(.callout).foregroundStyle(.secondary)
            }

            ForEach(check.issues, id: \.message) { issue in
                Label(issue.message, systemImage: issue.blocks ? "exclamationmark.octagon.fill" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(issue.blocks ? .red : .orange)
            }

            HStack {
                switch piece.status {
                case .drafted:
                    Button("Approve") { Task { await model.setStatus(.approved, of: piece) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(check.issues.contains { $0.blocks })
                        .help(check.issues.contains { $0.blocks } ? "Fix the red items first" : "Mark ready to post")
                case .approved:
                    Button { model.copyAndOpen(piece) } label: { Label("Copy & Open \(piece.platform.name)", systemImage: "arrow.up.forward.app") }
                        .buttonStyle(.borderedProminent)
                    Button("Back to Draft") { Task { await model.setStatus(.drafted, of: piece) } }
                case .published, .archived:
                    EmptyView()
                }
                Spacer()
            }
        }
        // Saves after a pause in typing.
        .task(id: piece.body + piece.parts.joined()) {
            try? await Task.sleep(for: .seconds(1))
            await model.saveContent(piece.id)
        }
    }

    private var formatName: String {
        switch piece.format {
        case "carousel": "Carousel · \(piece.parts.count) slides"
        case "reel_script": "Reel script · \(piece.parts.count) shots"
        case "thread": "Thread · \(piece.parts.count) posts"
        default: "Post"
        }
    }

    private func partLabel(_ index: Int) -> String {
        switch piece.format {
        case "carousel": "Slide \(index + 1)"
        case "reel_script": "Shot \(index + 1)"
        default: "\(index + 1)/\(piece.parts.count)"
        }
    }

    private var bodyBinding: Binding<String> {
        Binding(get: { piece.body }, set: { text in
            var changed = piece
            changed.body = text
            model.edit(changed)
        })
    }

    private func partBinding(_ index: Int) -> Binding<String> {
        Binding(get: { index < piece.parts.count ? piece.parts[index] : "" }, set: { text in
            guard index < piece.parts.count else { return }
            var changed = piece
            changed.parts[index] = text
            model.edit(changed)
        })
    }
}

extension AppModel {
    /// Puts the post on the clipboard and opens the platform's composer (pre-filled where it allows), then marks it posted.
    func copyAndOpen(_ piece: ContentPiece) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(piece.postText, forType: .string)
        var url: URL?
        switch piece.platform {
        case .x:
            var c = URLComponents(string: "https://x.com/intent/post")
            // One post fills the composer; a thread is on the clipboard to paste post by post.
            if piece.parts.count <= 1 { c?.queryItems = [URLQueryItem(name: "text", value: piece.postText)] }
            url = c?.url
        case .linkedin:
            var c = URLComponents(string: "https://www.linkedin.com/feed/")
            c?.queryItems = [URLQueryItem(name: "shareActive", value: "true"), URLQueryItem(name: "text", value: piece.postText)]
            url = c?.url
        case .instagram:
            url = URL(string: "https://www.instagram.com/") // no web composer: the caption is on the clipboard
        }
        if let url { NSWorkspace.shared.open(url) }
        Task { await setStatus(.published, of: piece) }
    }
}

/// The writing check's score, coloured so a glance is enough.
private struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((score >= 80 ? Color.green : score >= 50 ? .orange : .red).opacity(0.2), in: .capsule)
            .foregroundStyle(score >= 80 ? Color.green : score >= 50 ? .orange : .red)
            .help("Writing check: 100 means no AI-sounding phrases and within the platform's limits")
            .accessibilityLabel("Writing check \(score) out of 100")
    }
}

/// Who you are online and how you write: drafts and ideas follow it, and the writing check flags words you never use.
private struct VoiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page = ""
    @State private var audience = ""
    @State private var topics = ""
    @State private var notes = ""
    @State private var neverSay = ""

    var body: some View {
        Form {
            Section {
                TextField("Your page", text: $page, prompt: Text("e.g. @uxabhi on Instagram: UX tips and design breakdowns"))
                TextField("Who it's for", text: $audience, prompt: Text("e.g. junior designers and devs who want better UX"), axis: .vertical)
                    .lineLimit(1...3)
                TextField("Your topics", text: $topics, prompt: Text("e.g. UX mistakes, app teardowns, design tools, building Blink"), axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("Your page")
            } footer: {
                Text("Ideas and drafts use this to be specific to your field instead of generic.")
            }
            Section {
                TextField("How you sound", text: $notes,
                          prompt: Text("e.g. Short sentences, friendly, a bit dry. I show real screens, not theory."),
                          axis: .vertical)
                    .lineLimit(2...6)
                TextField("Words you never say", text: $neverSay, prompt: Text("e.g. hustle, synergy, crushing it"))
            } header: {
                Text("Your voice")
            } footer: {
                Text("Words separated by commas. Drafts avoid them and the writing check flags them. Blink never invents facts about you.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let words = neverSay.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    Task {
                        await model.saveVoice(VoiceProfile(page: trim(page), audience: trim(audience), topics: trim(topics),
                                                           notes: trim(notes), neverSay: words))
                    }
                    dismiss()
                }
            }
        }
        .onAppear {
            page = model.voice.page
            audience = model.voice.audience
            topics = model.voice.topics
            notes = model.voice.notes
            neverSay = model.voice.neverSay.joined(separator: ", ")
        }
    }
}
#endif
