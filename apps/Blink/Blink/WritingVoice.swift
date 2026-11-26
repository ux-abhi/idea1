// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI
import UniformTypeIdentifiers

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
