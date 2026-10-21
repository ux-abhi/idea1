// © Pexilim
import BlinkKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Which AI app the owner is connecting Blink to, with that app's own steps.
enum ConnectorApp: String, Identifiable {
    case chatGPT = "ChatGPT", claude = "Claude"
    var id: String { rawValue }

    var steps: [String] {
        switch self {
        case .claude: ["Open Claude › Settings › Connectors.", "Click Add custom connector, name it Blink, and paste the link.",
                       "Ask Claude: “What's on my schedule this week?”"]
        case .chatGPT: ["Open ChatGPT › Settings › Apps & Connectors › Advanced, and turn on Developer mode.",
                        "Click Create, name it Blink, paste the link, and pick No authentication.",
                        "Ask ChatGPT: “Any mail waiting for my reply?”"]
        }
    }
}

#if os(macOS)

/// Connect ChatGPT or Claude: one button makes Blink's link, then three steps in that app. The AI app's own plan pays.
struct ConnectorSheet: View {
    @Environment(AppModel.self) private var model
    let app: ConnectorApp
    let done: () -> Void
    @State private var link: URL?
    @State private var copied = false
    @State private var problem: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect \(app.rawValue)").font(.title2.weight(.semibold))
            Text("Ask \(app.rawValue) about your day, tasks and mail, or have it add tasks and notes, using your own \(app.rawValue) plan. It can't send mail or delete anything.")
                .foregroundStyle(.secondary)
            if let link {
                HStack {
                    Text(link.absoluteString).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button(copied ? "Copied" : "Copy Link") { copy(link) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(copied ? "Link copied" : "Copy link")
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(app.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
                Text("Keep this link private: anyone with it can read your day and mail summaries. Turn links off any time under Advanced.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await create() }
                } label: {
                    if working { ProgressView().controlSize(.small) } else { Text("Make My Link") }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(working)
            }
            if let problem { Text(problem).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func copy(_ link: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
        // A secret: clipboard managers (Blink's own history included) skip concealed items.
        NSPasteboard.general.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        copied = true
    }

    private func create() async {
        guard let server = model.server else { return }
        working = true
        defer { working = false }
        do {
            let made = try await server.createConnectorLink()
            link = made
            copy(made)
        } catch {
            problem = "Couldn't make a link. Check your connection and try again."
        }
    }
}

/// Advanced: the links Claude or ChatGPT use, when each was last used, and one button to turn them all off.
struct ConnectorLinks: View {
    @Environment(AppModel.self) private var model
    @State private var links: [BlinkServer.ConnectorLink] = []
    @State private var problem: String?
    @State private var confirming = false

    var body: some View {
        LabeledContent {
            if !links.isEmpty {
                Button("Turn Off All…", role: .destructive) { confirming = true }
                    .confirmationDialog("Turn off all links?", isPresented: $confirming) {
                        Button("Turn Off", role: .destructive) { Task { await revoke() } }
                    } message: {
                        Text("ChatGPT and Claude lose access to Blink at once. You can make a new link any time.")
                    }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Links for the ChatGPT and Claude apps")
                Text(links.isEmpty ? "None yet" : links.map { $0.lastUsedAt.map { "used \($0.formatted(.relative(presentation: .named)))" } ?? "not used yet" }
                    .formatted(.list(type: .and)))
                    .font(.caption).foregroundStyle(.secondary)
                if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
            }
        }
        .task { await load() }
    }

    private func load() async {
        links = (try? await model.server?.connectorLinks()) ?? []
    }

    private func revoke() async {
        do {
            try await model.server?.revokeConnectorLinks()
            await load()
        } catch {
            problem = "Couldn't turn them off. Check your connection."
        }
    }
}
#endif
