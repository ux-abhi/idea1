// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import SwiftUI

/// Settings › Connections › "Use Blink in Claude or ChatGPT": a link to add as a custom connector, so the owner's own
/// AI subscription can read their day, tasks and mail summaries and add tasks and notes. The link is shown once.
struct ConnectorSection: View {
    @Environment(AppModel.self) private var model
    @State private var links: [BlinkServer.ConnectorLink] = []
    @State private var fresh: URL?
    @State private var copied = false
    @State private var problem: String?
    @State private var working = false

    var body: some View {
        Section {
            if let fresh {
                HStack {
                    Text(fresh.absoluteString).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button(copied ? "Copied" : "Copy Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fresh.absoluteString, forType: .string)
                        // A secret: clipboard managers (Blink's own history included) skip concealed items.
                        NSPasteboard.general.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                        copied = true
                    }
                    .accessibilityLabel(copied ? "Connector link copied" : "Copy connector link")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("**Claude:** Settings › Connectors › Add custom connector › paste the link.")
                    Text("**ChatGPT:** Settings › Apps & Connectors › Advanced › Developer mode on › Create › paste the link, No authentication.")
                    Text("This link is shown only now. Anyone with it can read your day and mail summaries, so keep it private.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            HStack {
                Button(links.isEmpty ? "Create Connector Link" : "Create Another Link") { Task { await create() } }
                    .disabled(working)
                if !links.isEmpty {
                    Button("Turn Off All Links", role: .destructive) { Task { await revoke() } }.disabled(working)
                }
                if working { ProgressView().controlSize(.small) }
            }
            if let problem { Text(problem).foregroundStyle(.orange) }
            ForEach(links) { link in
                LabeledContent("Link made \(link.createdAt.formatted(date: .abbreviated, time: .omitted))",
                               value: link.lastUsedAt.map { "used \($0.formatted(.relative(presentation: .named)))" } ?? "not used yet")
            }
        } header: {
            Text("Use Blink in Claude or ChatGPT")
        } footer: {
            Text("Ask Claude or ChatGPT about your day, tasks and mail, or have them add tasks and notes, using your own subscription. They can't send mail or delete anything.")
        }
        .task { await load() }
    }

    private func load() async {
        guard let server = model.server else { return }
        links = (try? await server.connectorLinks()) ?? []
    }

    private func create() async {
        guard let server = model.server else { return }
        working = true
        defer { working = false }
        problem = nil
        do {
            fresh = try await server.createConnectorLink()
            copied = false
            await load()
        } catch {
            problem = "Couldn't make a link. Is your server up to date? Check your connection."
        }
    }

    private func revoke() async {
        guard let server = model.server else { return }
        working = true
        defer { working = false }
        do {
            try await server.revokeConnectorLinks()
            fresh = nil
            await load()
        } catch {
            problem = "Couldn't turn the links off. Check your connection."
        }
    }
}
#endif
