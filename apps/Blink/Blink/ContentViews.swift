// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI
import UniformTypeIdentifiers

/// The day a post goes out: "Add day", or the day; click to pick another or take it off the plan.
struct DayChip: View {
    @Binding var day: String?
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            Label(day.map { HabitDay.label($0) } ?? "Add Day", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(day == HabitDay.key(.now) ? Color.orange : day == nil ? .secondary : .primary)
        }
        .buttonStyle(.borderless)
        .help("The day it goes out")
        .popover(isPresented: $picking) {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker("Post on", selection: Binding(
                    get: { day.flatMap { HabitDay.date(fromKey: $0) } ?? .now },
                    set: { day = HabitDay.key($0) }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                if day != nil {
                    Button("Remove Day", role: .destructive) { day = nil; picking = false }
                }
            }
            .padding(12)
        }
    }
}

/// Where a post is: Idea → Draft → Ready → Posted.
struct StatusChip: View {
    let status: ContentPiece.Status

    static func name(_ status: ContentPiece.Status) -> String {
        switch status {
        case .idea: "Idea"
        case .drafted: "Draft"
        case .approved: "Ready"
        case .published: "Posted"
        case .archived: "Archived"
        }
    }

    var body: some View {
        let tint: Color = switch status {
        case .idea: .purple
        case .approved: .green
        case .published: .blue
        default: .secondary
        }
        Text(Self.name(status))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tint.opacity(0.15), in: .capsule)
            .foregroundStyle(tint)
    }
}

/// One post, opened: the full editor, and Blink's questions for its idea.
/// Also opened from a Space's canvas, so a post can be read and edited without leaving the Space.
struct PieceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.content.first { $0.id == id }?.idea ?? "Post").font(.headline).lineLimit(1)
                Spacer()
                // Esc, not Return: Return belongs to the slide fields.
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                if let piece = model.content.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let asked = model.questions[piece.idea], !asked.isEmpty, piece.status == .drafted {
                            QuestionsBox(idea: piece.idea, questions: asked,
                                         platforms: Array(Set(model.content.filter { $0.idea == piece.idea }.map(\.platform))))
                        }
                        PieceEditor(piece: piece)
                    }
                    .padding(16)
                } else {
                    ContentUnavailableView("This post is gone", systemImage: "trash")
                }
            }
        }
        .frame(width: 640, height: 640)
        // Deleted (here or elsewhere): close, the Undo chip brings it back.
        .onChange(of: model.content.contains { $0.id == id }) { _, here in if !here { dismiss() } }
        // Edits save a second after typing stops; closing sooner must not lose them.
        .onDisappear { Task { await model.saveContent(id) } }
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
                DayChip(day: Binding(get: { piece.plannedFor }, set: { day in Task { await model.setDay(day, of: piece) } }))
                Spacer()
                ScoreBadge(score: check.score)
                Menu {
                    Button("Delete Post", role: .destructive) { Task { await model.deletePost(piece) } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("More")
            }
            // The first line people see, and the card's title on a Space.
            TextField("Hook: the opening line", text: hookBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .lineLimit(1...3)

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

            PieceMedia(piece: piece, handle: model.voice.page)

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
                    Button("Mark as Posted") { Task { await model.setStatus(.published, of: piece) } }
                    Button("Back to Draft") { Task { await model.setStatus(.drafted, of: piece) } }
                case .idea:
                    Button("Write") { Task { await model.write(piece) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.drafting)
                case .published, .archived:
                    EmptyView()
                }
                Spacer()
            }
        }
        // Saves after a pause in typing.
        .task(id: piece.hook + piece.body + piece.parts.joined()) {
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

    private var hookBinding: Binding<String> {
        Binding(get: { piece.hook }, set: { text in
            var changed = piece
            changed.hook = MoneyMath.clip(text, to: 500) // what the server takes
            model.edit(changed)
        })
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

/// What the model asked to know for a stronger post; the owner's answers redraft the idea with those facts.
private struct QuestionsBox: View {
    @Environment(AppModel.self) private var model
    let idea: String
    let questions: [String]
    let platforms: [ContentPiece.Platform]
    @State private var answers = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Blink needs a few facts to make this stronger", systemImage: "questionmark.bubble")
                .font(.callout.weight(.semibold))
            ForEach(questions, id: \.self) { Text("• \($0)").font(.callout) }
            TextField("Your answers, e.g. \"my app had 140 users; I paused features in June\"", text: $answers, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
            HStack {
                Button("Redraft with Answers") { Task { await model.redraft(idea: idea, answers: answers, platforms: platforms) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(answers.trimmingCharacters(in: .whitespaces).isEmpty || model.drafting)
                Button("Keep as Is") { model.dismissQuestions(for: idea) }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
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
        if let url { NSWorkspace.shared.open(url) } // posted only when the owner says so: opening isn't posting
    }
}

/// A draft's picture, only once the owner asks for it: carousel slides drawn on the Mac (over one FLUX background, if
/// made), or a cover image. Slides drag into any app; Export… writes PNGs to a folder you pick.
private struct PieceMedia: View {
    @Environment(AppModel.self) private var model
    let piece: ContentPiece
    let handle: String
    /// Decoded once per draft and new image, off the main thread, not on every keystroke in the draft.
    @State private var image: NSImage?

    var body: some View {
        let carousel = piece.format == "carousel" && !piece.parts.isEmpty
        let asked = model.designed.contains(piece.id)
        VStack(alignment: .leading, spacing: 8) {
                if carousel && asked {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(piece.parts.indices, id: \.self) { index in
                                slide(index, background: image)
                                    .frame(width: 1080, height: 1350)
                                    .scaleEffect(0.12, anchor: .topLeading)
                                    .frame(width: 130, height: 162, alignment: .topLeading)
                                    .clipShape(.rect(cornerRadius: 8))
                                    .onDrag { provider(for: render(slide(index, background: image)), name: "slide-\(index + 1)") }
                                    .accessibilityLabel("Slide \(index + 1): \(piece.parts[index])")
                            }
                        }
                    }
                } else if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: 200, height: 200).clipShape(.rect(cornerRadius: 10))
                        .onDrag { NSItemProvider(contentsOf: PostMedia.url(for: piece.id)) ?? NSItemProvider() }
                        .accessibilityLabel("Cover image")
                }
                HStack(spacing: 8) {
                    if carousel && !asked {
                        Button { model.design(piece) } label: { Label("Design Slides", systemImage: "square.stack") }
                            .help("Draw this carousel's slides with your text (free, on your Mac)")
                    }
                    if !carousel || asked {
                    Button {
                        Task { await model.makeImage(for: piece) }
                    } label: {
                        if model.makingImage.contains(piece.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(image == nil ? (carousel ? "Make Background" : "Make Image") : "New Image", systemImage: "photo.badge.plus")
                        }
                    }
                    .disabled(model.makingImage.contains(piece.id))
                    .help("A free image made for this post; the text is drawn on your Mac")
                    }
                    if (carousel && asked) || image != nil {
                        Button("Export…") { export(carousel: carousel, background: image) }
                    }
                }
                .controlSize(.small)
        }
        .task(id: "\(piece.id)-\(model.mediaVersion)") { // reload after a new image
            let url = PostMedia.url(for: piece.id)
            image = await Task.detached { FileManager.default.fileExists(atPath: url.path) ? NSImage(contentsOf: url) : nil }.value
        }
    }

    private func slide(_ index: Int, background: NSImage?) -> some View {
        SlideView(text: piece.parts[index], index: index, total: piece.parts.count,
                  handle: handle.split(separator: " ").first.map(String.init) ?? "", background: background)
    }

    private func render(_ view: some View) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: 1080, height: 1350))
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func provider(for data: Data?, name: String) -> NSItemProvider {
        let provider = NSItemProvider()
        if let data {
            provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { done in
                done(data, nil)
                return nil
            }
        }
        provider.suggestedName = name
        return provider
    }

    /// Writes slide-01.png… (or cover.jpg) into a folder the owner picks, then shows them in Finder.
    private func export(carousel: Bool, background: NSImage?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for this post's images"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        var written: [URL] = []
        if carousel {
            for index in piece.parts.indices {
                let file = folder.appending(path: String(format: "slide-%02d.png", index + 1))
                if let data = render(slide(index, background: background)), (try? data.write(to: file)) != nil { written.append(file) }
            }
        } else if let data = try? Data(contentsOf: PostMedia.url(for: piece.id)) {
            let file = folder.appending(path: "cover.jpg")
            if (try? data.write(to: file)) != nil { written.append(file) }
        }
        if !written.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(written) }
    }
}

/// One 1080 × 1350 carousel slide: the first over the background image, the rest on a dimmed version of it; big, crisp text.
struct SlideView: View {
    let text: String
    let index: Int
    let total: Int
    let handle: String
    let background: NSImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let background {
                    Image(nsImage: background).resizable().scaledToFill()
                        .blur(radius: index == 0 ? 0 : 30)
                } else {
                    LinearGradient(colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 1080, height: 1350)
            .clipped()
            LinearGradient(colors: [.black.opacity(index == 0 ? 0.2 : 0.55), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text(text)
                    .font(.system(size: index == 0 ? 92 : 68, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(8)
                    .minimumScaleFactor(0.5)
                Spacer()
                HStack {
                    Text(handle).font(.system(size: 34, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(index + 1)/\(total)").font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            .padding(90)
        }
        .frame(width: 1080, height: 1350)
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
struct VoiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page = ""
    @State private var audience = ""
    @State private var topics = ""
    @State private var notes = ""
    @State private var neverSay = ""
    @State private var brief = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $brief)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 140)
                HStack {
                    Button("Import File…", action: importBrief)
                    if !brief.isEmpty { Button("Clear", role: .destructive) { brief = "" } }
                    Spacer()
                    Text("\(brief.count.formatted()) of \(VoiceProfile.briefLimit.formatted()) characters")
                        .font(.caption).foregroundStyle(brief.count > VoiceProfile.briefLimit ? .red : .secondary)
                }
            } header: {
                Text("Creator brief")
            } footer: {
                Text("Your story, projects, numbers, content pillars and rules, e.g. a Markdown file. Drafts, ideas and your week plan use only its facts, and its writing rules come first. Kept on your server.")
            }
            Section {
                TextField("Your page", text: $page, prompt: Text("e.g. @yourname on Instagram: UX tips and design breakdowns"))
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
        .frame(width: 540, height: 640)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let words = neverSay.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    Task {
                        await model.saveVoice(VoiceProfile(page: trim(page), audience: trim(audience), topics: trim(topics),
                                                           notes: trim(notes), neverSay: words, brief: trim(brief)))
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
            brief = model.voice.brief
        }
    }

    /// A Markdown or text file the owner picks (user-selected read access only).
    private func importBrief() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .init(filenameExtension: "md") ?? .plainText]
        panel.message = "Choose your creator brief (a Markdown or text file)"
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        brief = String(text.prefix(VoiceProfile.briefLimit))
    }
}
#endif
