// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI
import UniformTypeIdentifiers

/// Bulk Mail (ADR-0003): one description and a contact list become a personal mail for each person, reviewed here and
/// saved to Drafts. Nothing is sent from this screen.
struct BulkMailView: View {
    @Environment(AppModel.self) private var model
    let back: () -> Void
    @AppStorage("bulk.selected") private var selected: String?
    @State private var creating = false
    @State private var deleting: MailCampaign?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Button("Inbox", systemImage: "chevron.left", action: back).buttonStyle(.borderless)
                HStack {
                    Text("Bulk Mail").font(.system(.title, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("New Bulk Mail", systemImage: "plus") { creating = true }.labelStyle(.iconOnly).help("New Bulk Mail")
                }
                List(selection: $selected) {
                    ForEach(model.campaigns) { campaign in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(campaign.title).lineLimit(1)
                            Text(summary(campaign)).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(campaign.id)
                        .contextMenu { Button("Delete Bulk Mail…", systemImage: "trash", role: .destructive) { deleting = campaign } }
                    }
                }
                .onDeleteCommand { deleting = model.campaigns.first { $0.id == selected } }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            .frame(width: 260)
            Divider()
            Group {
                if let id = selected, let campaign = model.campaigns.first(where: { $0.id == id }) {
                    CampaignView(campaign: campaign).id(campaign.id)
                } else {
                    ContentUnavailableView {
                        Label("Write to many people at once", systemImage: "envelope.badge.person.crop")
                    } description: {
                        Text("Describe what you want to say and add a contact list. Blink writes a personal mail for each person, you check them, and they go to your Drafts.")
                    } actions: {
                        Button("New Bulk Mail") { creating = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await model.loadCampaigns() }
        .sheet(isPresented: $creating, onDismiss: { model.bulkFromTable = nil }) {
            NewCampaignSheet(preset: model.bulkFromTable) { selected = $0 }
        }
        .onChange(of: model.bulkFromTable, initial: true) { if model.bulkFromTable != nil { creating = true } }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Bulk Mail", role: .destructive) {
                guard let campaign = deleting else { return }
                if selected == campaign.id { selected = nil }
                Task { await model.delete(campaign) }
            }
        } message: {
            Text("Its contacts and mails are deleted from Blink. Mails already sent, and drafts already in your mailbox, stay there.")
        }
    }

    private func summary(_ campaign: MailCampaign) -> String {
        let people = model.bulkRecipients[campaign.id]
        guard let people else { return EmailMessage.accountName(campaign.account) }
        let drafts = people.filter { $0.status == .inDrafts }.count
        return "\(people.count) people" + (drafts > 0 ? " · \(drafts) in Drafts" : "")
    }
}

/// The batch's description, the mailbox it comes from, and the contacts.
/// A new bulk mail in three steps: who you're writing to (one of your tables, or a pasted list), what you want to say,
/// and the last details. A table gives only its own rows; nothing else from its Space is pulled in unless asked.
private struct NewCampaignSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// A table to start from (picked from its own menu).
    var preset: String?
    let created: (String) -> Void
    @State private var step = 1
    @State private var fromTable = true
    @State private var source = ""      // the chosen table block's id
    @State private var tag = ""
    @State private var title = ""
    @State private var context = ""
    @State private var goal = ""
    @State private var tone = ""
    @State private var account = ""
    @State private var research = true
    @State private var contacts = ""
    @State private var importing = false
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Step \(step) of 3").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(["Who are you writing to?", "What do you want to say?", "Last details"][step - 1]).font(.title2.bold())
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { i in
                        Capsule().fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25)).frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(24)
            Group {
                switch step {
                case 1: whoStep
                case 2: whatStep
                default: detailsStep
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if step > 1 { Button("Back") { step -= 1 } }
                if step < 3 {
                    Button("Next") { advance() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!ready)
                } else {
                    Button("Create Bulk Mail") { create() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(working || title.trimmingCharacters(in: .whitespaces).isEmpty || account.isEmpty)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 600)
        .onAppear { account = model.mailAccounts.first ?? "" }
        .task {
            for space in model.spaces where model.spaceBlocks[space.id] == nil { await model.loadBlocks(space) }
            for item in tables where model.tableRows[item.block.id] == nil { await model.loadRows(item.block) }
            if let preset, tables.contains(where: { $0.block.id == preset }) { source = preset }
            else if source.isEmpty { source = tables.first?.block.id ?? "" }
            if tables.isEmpty { fromTable = false }
        }
        .onChange(of: source) { tag = "" }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .tabSeparatedText]) { result in
            guard let file = try? result.get() else { return }
            let access = file.startAccessingSecurityScopedResource()
            defer { if access { file.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: file, encoding: .utf8) { contacts = String(text.prefix(2_000_000)) }
        }
    }

    // MARK: Step 1: who

    @ViewBuilder
    private var whoStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Contacts from", selection: $fromTable) {
                Text("One of my tables").tag(true)
                Text("Paste a list").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden()
            if fromTable {
                if tables.isEmpty {
                    Text("You have no tables yet. Add one on a Space's page (type /table), or paste a list instead.").foregroundStyle(.secondary)
                } else {
                    Picker("Table", selection: $source) {
                        ForEach(model.spaces.filter { space in tables.contains { $0.space.id == space.id } }) { space in
                            Section(space.title) {
                                ForEach(tables.filter { $0.space.id == space.id }, id: \.block.id) { Text(name(of: $0.block)).tag($0.block.id) }
                            }
                        }
                    }
                    if let chosen {
                        let rows = model.tableRows[chosen.block.id] ?? []
                        let columns = chosen.block.data.columns ?? []
                        let tags = SpaceTable.allTags(columns: columns, rows: rows)
                        if !tags.isEmpty {
                            Picker("Who", selection: $tag) {
                                Text("Everyone in the table").tag("")
                                ForEach(tags, id: \.self) { Text("Only rows tagged #\($0)").tag($0) }
                            }
                        }
                        let found = SpaceTable.contacts(columns: columns, rows: rows, tag: tag)
                        preview(found.contacts.map(\.contact), problem: found.problems.first { $0.hasPrefix("No column") })
                    }
                }
            } else {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $contacts).font(.body.monospaced()).scrollContentBackground(.hidden).padding(6)
                        .background(.background.secondary, in: .rect(cornerRadius: 8)).accessibilityLabel("Contacts")
                    if contacts.isEmpty {
                        Text("Ana Silva <ana@studio.com>\nben@acme.io").font(.body.monospaced()).foregroundStyle(.tertiary)
                            .padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
                    }
                }
                .frame(height: 180)
                HStack {
                    Text("One person per line, or a CSV with an email column.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Import CSV…") { importing = true }
                }
                preview(ContactList.parse(contacts).contacts, problem: nil)
            }
        }
    }

    /// Who it will go to, so there's no doubt which list is being used.
    @ViewBuilder
    private func preview(_ people: [ContactList.Contact], problem: String?) -> some View {
        if let problem {
            Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        } else if !people.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(people.count) \(people.count == 1 ? "person" : "people")").font(.headline)
                Text(people.prefix(4).map { $0.name.isEmpty ? $0.email : "\($0.name) (\($0.email))" }.joined(separator: ", ")
                     + (people.count > 4 ? " and \(people.count - 4) more" : ""))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 8))
        }
    }

    // MARK: Step 2: what

    private var whatStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who you are and why you're writing").font(.headline)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $context).scrollContentBackground(.hidden).padding(6)
                        .background(.background.secondary, in: .rect(cornerRadius: 8)).accessibilityLabel("Who you are and why you're writing")
                    if context.isEmpty {
                        Text("I'm a product designer looking for a junior role. My portfolio: blinkk.app/work. I like teams building tools for creators.")
                            .foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
                    }
                }
                .frame(height: 150)
                HStack {
                    Text("The mails only use what you write here and what's in each person's row.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let chosen, fromTable, !model.spaceContext(chosen.space).isEmpty {
                        Button("Use Notes from \(chosen.space.title)") {
                            let notes = model.spaceContext(chosen.space)
                            context = String((context.isEmpty ? notes : context + "\n\n" + notes).prefix(8000))
                        }
                        .help("Adds the text, notes and files on that Space's page")
                    }
                }
            }
            LabeledContent("What you want back") { TextField("A short call, a reply", text: $goal).textFieldStyle(.roundedBorder).frame(width: 300) }
            LabeledContent("Tone") { TextField("Your usual voice", text: $tone).textFieldStyle(.roundedBorder).frame(width: 300) }
        }
    }

    // MARK: Step 3: details

    private var detailsStep: some View {
        Form {
            TextField("Name", text: $title, prompt: Text("Founders outreach"))
            Picker("Send from", selection: $account) {
                ForEach(model.mailAccounts, id: \.self) { Text(EmailMessage.accountName($0)).tag($0) }
            }
            Toggle(isOn: $research) {
                Text("Read each company's website")
                Text("For one personal detail in each mail. Read once per company.")
            }
            if model.mailAccounts.isEmpty {
                Label("Connect a mailbox in Settings › Connections first.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Text("Next, Blink writes 3 sample mails for you to check before it writes the rest. Nothing is sent without your OK.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.horizontal, -20)
    }

    // MARK: Logic

    /// Every table in every Space (the address column is found even if it isn't typed Email).
    private var tables: [(space: Space, block: SpaceBlock)] {
        model.spaces.flatMap { space in (model.spaceBlocks[space.id] ?? []).filter { $0.kind == .table }.map { (space, $0) } }
    }

    private var chosen: (space: Space, block: SpaceBlock)? { tables.first { $0.block.id == source } }

    private func name(of block: SpaceBlock) -> String { (block.data.text ?? "").isEmpty ? "Untitled table" : block.data.text! }

    private var ready: Bool {
        switch step {
        case 1:
            if fromTable, let chosen {
                return !SpaceTable.contacts(columns: chosen.block.data.columns ?? [], rows: model.tableRows[chosen.block.id] ?? [], tag: tag).contacts.isEmpty
            }
            return !fromTable ? !ContactList.parse(contacts).contacts.isEmpty : false
        case 2: return !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    private func advance() {
        // The name starts as the table's (and its tag), so the bulk mail is easy to find later.
        if step == 1, title.isEmpty, fromTable, let chosen { title = name(of: chosen.block) + (tag.isEmpty ? "" : " #\(tag)") }
        step += 1
    }

    private func create() {
        working = true
        var campaign = MailCampaign(title: String(title.trimmingCharacters(in: .whitespaces).prefix(200)), context: String(context.prefix(8000)),
                                    goal: String(goal.prefix(1000)), tone: String(tone.prefix(500)), account: account, research: research)
        let table = fromTable ? chosen : nil
        if let table { (campaign.spaceID, campaign.tableBlock, campaign.tag) = (table.space.id, table.block.id, tag) }
        Task {
            defer { working = false }
            guard await model.newCampaign(campaign) else { return }
            let problems = table != nil ? await model.importFromTable(campaign) : await model.addContacts(contacts, to: campaign)
            UserDefaults.standard.set(problems, forKey: "bulk.problems.\(campaign.id)")
            created(campaign.id)
            dismiss()
            // Writing starts by itself: everyone when it's a few people, else 3 samples to check the style on first.
            let ids = (model.bulkRecipients[campaign.id] ?? []).map(\.id)
            await model.writeMails(ids.count <= 5 ? ids : Array(ids.prefix(3)), in: campaign)
        }
    }
}

/// One bulk mail: the steps along the top, the people on the left, the selected person's mail on the right.
private struct CampaignView: View {
    @Environment(AppModel.self) private var model
    let campaign: MailCampaign
    @State private var picked: String?
    @State private var note = ""
    @State private var problems: [String] = []
    @State private var adding = false
    @State private var confirmDelete = false
    @State private var warnings: [String: [String]] = [:]
    @State private var confirmSend = false

    private var people: [MailRecipient] { model.bulkRecipients[campaign.id] ?? [] }

    var body: some View {
        let people = people
        let fresh = people.filter { $0.status == .new }
        let written = people.filter { $0.status == .written }
        let approved = people.filter { $0.status == .approved }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(campaign.title).font(.title2.bold())
                Text("from \(EmailMessage.accountName(campaign.account))").foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Add Contacts…", systemImage: "person.badge.plus") { adding = true }
                    if campaign.tableBlock != nil {
                        Button("Refresh from Table", systemImage: "arrow.clockwise") { Task { problems = await model.importFromTable(campaign) } }
                    }
                    Divider()
                    Button("Delete Bulk Mail…", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Bulk mail options")
            }
            steps(fresh: fresh, written: written, approved: approved)
            AttachmentsRow(campaign: model.campaigns.first { $0.id == campaign.id } ?? campaign)
            if !problems.isEmpty { problemBox }
            HStack(spacing: 0) {
                List(selection: $picked) {
                    ForEach(ordered(people)) { person in
                        PersonRow(person: person, warned: !(warnings[person.id] ?? []).isEmpty).tag(person.id)
                            .contextMenu {
                                Button("Remove from This Bulk Mail", systemImage: "person.badge.minus") { Task { await model.remove(person) } }
                                Button("Never Mail in Bulk Again", systemImage: "hand.raised") { Task { await model.remove(person, forever: true) } }
                            }
                    }
                }
                .onDeleteCommand { if let person = people.first(where: { $0.id == picked }) { Task { await model.remove(person) } } }
                .listStyle(.plain)
                .frame(width: 280)
                Divider()
                if let id = picked, let person = people.first(where: { $0.id == id }) {
                    MailEditor(person: person, campaign: campaign, warnings: warnings[person.id] ?? []).id(person.id)
                } else {
                    ContentUnavailableView(people.isEmpty ? "No contacts yet" : "Pick someone to see their mail",
                                           systemImage: people.isEmpty ? "person.2" : "envelope")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 10))
            Label("Blink sends slowly so your account stays in good standing: one mail every 5 minutes, 8:00–20:00, up to the daily limit, and it pauses if your mail provider objects.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .task {
            await model.loadRecipients(campaign)
            problems = UserDefaults.standard.stringArray(forKey: "bulk.problems.\(campaign.id)") ?? []
        }
        // Show a real mail as soon as there is one, instead of an empty pane.
        .onChange(of: people.first { !$0.body.isEmpty }?.id) { _, first in if picked == nil { picked = first } }
        .task(id: people.map { "\($0.id)\($0.subject.count)\($0.body.count)\($0.status.rawValue)" }) {
            let mails = people.filter { $0.status == .written || $0.status == .approved }.map { (id: $0.id, subject: $0.subject, body: $0.body) }
            warnings = await Task.detached { MailLint.batch(mails) }.value
        }
        .sheet(isPresented: $adding) { AddContactsSheet(campaign: campaign) { problems = $0 } }
        .sheet(isPresented: $confirmSend) {
            SendBulkSheet(campaign: model.campaigns.first { $0.id == campaign.id } ?? campaign,
                          count: people.filter { $0.status == .approved }.count)
        }
        // While sending, the server works every 5 minutes: look again each minute so the counts move.
        .task(id: model.campaigns.first { $0.id == campaign.id }?.status) {
            while model.campaigns.first(where: { $0.id == campaign.id })?.status == .sending, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await model.loadRecipients(campaign)
                await model.loadCampaigns()
            }
        }
        .confirmationDialog("Delete “\(campaign.title)”?", isPresented: $confirmDelete) {
            Button("Delete Bulk Mail", role: .destructive) { Task { await model.delete(campaign) } }
        } message: {
            Text("Its contacts and mails are deleted from Blink. Drafts already in your mailbox stay there.")
        }
    }

    /// Where this bulk mail is (1 Write → 2 Check → 3 Send), one sentence on what to do now, and the one button for it.
    @ViewBuilder
    private func steps(fresh: [MailRecipient], written: [MailRecipient], approved: [MailRecipient]) -> some View {
        let live = model.campaigns.first { $0.id == campaign.id } ?? campaign
        // Finished: everyone is in Drafts, sent, skipped or replied, so nothing's left to write, check or send.
        let finished = !people.isEmpty && fresh.isEmpty && written.isEmpty && approved.isEmpty
        let stage = finished || live.status == .sending || live.status == .paused || (!approved.isEmpty && written.isEmpty && fresh.isEmpty) ? 3
            : !written.isEmpty || !approved.isEmpty ? 2 : 1
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Array(["Write", "Check", "Send"].enumerated()), id: \.offset) { i, name in
                    HStack(spacing: 6) {
                        Text("\(i + 1)").font(.caption.weight(.bold)).frame(width: 20, height: 20)
                            .background(i + 1 <= stage ? Color.accentColor : Color.secondary.opacity(0.25), in: .circle)
                            .foregroundStyle(i + 1 <= stage ? .white : .secondary)
                        Text(name).font(.callout.weight(i + 1 == stage ? .semibold : .regular)).foregroundStyle(i + 1 == stage ? .primary : .secondary)
                    }
                    if i < 2 { Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 28, height: 1) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(stage) of 3: \(["Write", "Check", "Send"][stage - 1])")
            HStack(spacing: 10) {
                if let working = model.bulkWorking {
                    ProgressView().controlSize(.small)
                    Text(working == "Writing…" ? "Blink is writing your mails. They appear on the left as they're done." : working).foregroundStyle(.secondary)
                } else if live.status == .sending || live.status == .paused {
                    sendingStatus(live)
                } else if finished {
                    let drafts = people.filter { $0.status == .inDrafts }.count, sent = people.filter { $0.status == .sent || $0.status == .replied }.count
                    Label([drafts > 0 ? "\(drafts) in Drafts" : nil, sent > 0 ? "\(sent) sent" : nil].compactMap { $0 }.joined(separator: " · ").isEmpty
                          ? "All done" : "All done · " + [drafts > 0 ? "\(drafts) in Drafts" : nil, sent > 0 ? "\(sent) sent" : nil].compactMap { $0 }.joined(separator: " · "),
                          systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Add More People…") { adding = true }
                } else if people.isEmpty {
                    Text("Add the people you want to write to.").foregroundStyle(.secondary)
                    Button("Add Contacts…") { adding = true }.buttonStyle(.borderedProminent)
                } else if written.isEmpty && approved.isEmpty {
                    Text("Nothing written yet.").foregroundStyle(.secondary)
                    Button(fresh.count > 5 ? "Write 3 Samples" : fresh.count == 1 ? "Write the Mail" : fresh.count == 2 ? "Write Both" : "Write All \(fresh.count)") {
                        Task { await model.writeMails(fresh.count <= 5 ? fresh.map(\.id) : fresh.prefix(3).map(\.id), in: campaign) }
                    }
                    .buttonStyle(.borderedProminent)
                } else if !fresh.isEmpty {
                    Text("Read the samples on the right. Not quite right? Add a note and rewrite.").foregroundStyle(.secondary).lineLimit(2)
                    TextField("e.g. shorter, less formal", text: $note).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    Button("Rewrite") { Task { await model.writeMails(written.map(\.id), in: campaign, note: note) } }
                        .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Looks Good, Write the Other \(fresh.count)") { Task { await model.writeMails(fresh.map(\.id), in: campaign, note: note) } }
                        .buttonStyle(.borderedProminent)
                } else if !written.isEmpty {
                    let warned = written.filter { !(warnings[$0.id] ?? []).isEmpty || $0.flags.contains("mailed_recently") }
                    Text(warned.isEmpty ? "All \(written.count) mails are written and look fine."
                         : "\(written.count) mails written. \(warned.count) \(warned.count == 1 ? "has a warning" : "have warnings") (at the top of the list).")
                        .foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    if !warned.isEmpty {
                        Button("Approve Only the \(written.count - warned.count) Without Warnings") {
                            Task { await model.approveAll(written.filter { w in !warned.contains { $0.id == w.id } }, in: campaign) }
                        }
                        .disabled(written.count == warned.count)
                    }
                    Button("Approve All \(written.count)") { Task { await model.approveAll(written, in: campaign) } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("\(approved.count) \(approved.count == 1 ? "mail is" : "mails are") ready.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Save to Drafts", systemImage: "tray.and.arrow.down") { Task { await model.saveBulkDrafts(campaign) } }
                        .help("Puts them in your Drafts folder, to send yourself from your mail app.")
                    Button("Send \(approved.count)…", systemImage: "paperplane") { confirmSend = true }
                        .buttonStyle(.borderedProminent)
                        .help("Blink sends them for you, slowly, after Touch ID.")
                }
            }
        }
    }

    /// While a batch goes out: how far it is, and Pause or Resume. Paused by Blink, it says why.
    @ViewBuilder
    private func sendingStatus(_ live: MailCampaign) -> some View {
        let sent = people.filter { $0.status == .sent || $0.status == .replied }.count
        let waiting = people.filter { $0.status == .approved }.count
        let failed = people.filter { $0.status == .failed }
        if live.status == .sending {
            ProgressView().controlSize(.small)
            Text("Sending · \(sent) sent, \(waiting) to go · one every 5 minutes, 8:00–20:00, up to \(live.dailyLimit) a day")
                .foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Pause", systemImage: "pause.fill") { Task { await model.setSending(false, for: live) } }
        } else {
            Image(systemName: "pause.circle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            Text("Paused · \(sent) sent, \(waiting) to go" + (failed.last?.error.map { ". Last problem: \($0)" } ?? ""))
                .foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            Button("Resume", systemImage: "play.fill") { Task { await model.setSending(true, for: live) } }
                .buttonStyle(.borderedProminent).disabled(waiting == 0)
        }
    }

    private var problemBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("\(problems.count) rows weren't added", systemImage: "exclamationmark.triangle").font(.callout.weight(.semibold))
                Spacer()
                Button("Dismiss") {
                    problems = []
                    UserDefaults.standard.removeObject(forKey: "bulk.problems.\(campaign.id)")
                }
                .buttonStyle(.borderless)
            }
            ScrollView { Text(problems.joined(separator: "\n")).font(.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(maxHeight: 80)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 8))
    }

    /// Written mails with warnings first (they need a look), then the rest in the order they were added.
    private func ordered(_ people: [MailRecipient]) -> [MailRecipient] {
        func rank(_ p: MailRecipient) -> Int {
            switch p.status {
            case .written: (warnings[p.id] ?? []).isEmpty && p.flags.allSatisfy({ $0 == "known" }) ? 1 : 0
            case .approved: 2
            case .new: 3
            default: 4
            }
        }
        return people.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }
}

private struct PersonRow: View {
    let person: MailRecipient
    let warned: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name.isEmpty ? person.email : person.name).lineLimit(1)
                Text(person.subject.isEmpty ? person.email : person.subject).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if warned || person.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Has warnings")
            }
            Text(Self.status(person.status)).font(.caption2.weight(.semibold)).foregroundStyle(Self.color(person.status))
        }
        .accessibilityElement(children: .combine)
    }

    static func status(_ status: MailRecipient.Status) -> String {
        switch status {
        case .new: "Not written"
        case .written: "To check"
        case .approved: "Approved"
        case .skipped: "Skipped"
        case .inDrafts: "In Drafts"
        case .sent: "Sent"
        case .failed: "Failed"
        case .bounced: "Bounced"
        case .replied: "Replied"
        }
    }

    static func color(_ status: MailRecipient.Status) -> Color {
        switch status {
        case .approved, .inDrafts, .sent, .replied: .green
        case .written: .blue
        case .failed, .bounced: .red
        default: .secondary
        }
    }
}

/// One person's mail: what Blink knows about them, its warnings, and the mail to edit, rewrite, approve or skip.
private struct MailEditor: View {
    @Environment(AppModel.self) private var model
    let person: MailRecipient
    let campaign: MailCampaign
    let warnings: [String]
    @State private var subject = ""
    @State private var text = ""
    @State private var note = ""
    @State private var editing = false

    private var locked: Bool { [.inDrafts, .sent, .replied, .bounced].contains(person.status) || signed }
    /// Approved into a batch that's sending: the text was signed with Touch ID, so it can't change, only be taken out.
    private var signed: Bool {
        let status = model.campaigns.first { $0.id == campaign.id }?.status
        return person.status == .approved && (status == .sending || status == .paused)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name.isEmpty ? person.email : person.name).font(.headline)
                        Text(person.email).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Menu {
                        Button("Remove from This Bulk Mail", systemImage: "person.badge.minus") { Task { await model.remove(person) } }
                        Button("Never Mail in Bulk Again", systemImage: "hand.raised") { Task { await model.remove(person, forever: true) } }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Contact options")
                }
                if !person.fields.isEmpty {
                    Text(person.fields.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                ForEach(notes, id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
                if !person.card.isEmpty { ResearchCardView(card: person.card) }
                if person.flags.contains("known") {
                    Label("You've mailed with them before, so the mail can mention it.", systemImage: "clock.arrow.circlepath").font(.callout).foregroundStyle(.secondary)
                }
                if person.status == .new && person.body.isEmpty {
                    HStack(spacing: 8) {
                        if model.bulkWorking != nil { ProgressView().controlSize(.small) }
                        Text(model.bulkWorking != nil ? "Being written…" : "Not written yet. Blink writes it with the others, or now:").foregroundStyle(.secondary)
                        if model.bulkWorking == nil { Button("Write It Now") { Task { await model.writeMails([person.id], in: campaign) } } }
                    }
                } else {
                    if editing && !locked {
                        TextField("Subject", text: $subject).textFieldStyle(.roundedBorder)
                        TextEditor(text: $text).font(.body).frame(minHeight: 240)
                            .scrollContentBackground(.hidden).padding(6)
                            .background(.background, in: .rect(cornerRadius: 8))
                            .accessibilityLabel("Mail text")
                        HStack {
                            Spacer()
                            Button("Done Editing") { save(person.status); editing = false }.keyboardShortcut(.return, modifiers: [.command, .shift])
                        }
                    } else {
                        MailPreview(to: person, from: campaign, subject: subject, text: text,
                                    files: model.campaigns.first { $0.id == campaign.id }?.attachments ?? campaign.attachments,
                                    edit: locked ? nil : { editing = true })
                    }
                    if !locked {
                        HStack {
                            TextField("Rewrite note, e.g. warmer, mention their museum project", text: $note).textFieldStyle(.roundedBorder)
                            Button("Rewrite") { Task { await model.writeMails([person.id], in: campaign, note: note); note = "" } }
                                .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty || model.bulkWorking != nil)
                        }
                        HStack {
                            Button("Skip") { save(.skipped) }
                            Spacer()
                            if person.status == .approved {
                                Button("Unapprove") { save(.written) }
                            } else {
                                Button("Approve") { save(.approved) }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                            }
                        }
                    } else if signed {
                        HStack {
                            Label("Signed for sending, so the text can't change.", systemImage: "touchid").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Don't Send This One") { Task { await model.takeOut(person) } }
                                .help("Takes this mail out of the batch. The others carry on.")
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear { (subject, text) = (person.subject, person.body) }
        .onChange(of: person) { _, now in (subject, text) = (now.subject, now.body) } // after a rewrite
        .onDisappear { if !locked, subject != person.subject || text != person.body { save(person.status) } }
    }

    private var notes: [String] {
        var lines = warnings
        if person.flags.contains("role") { lines.append("A shared inbox (like info@). Mail here often goes unread or is marked as spam.") }
        if person.flags.contains("mailed_recently") { lines.append("You mailed them from another bulk mail in the last 30 days.") }
        if person.flags.contains("no_mail_server") { lines.append("Their domain doesn't take mail, so this would bounce. Check the address.") }
        if let error = person.error { lines.append(error) }
        return lines
    }

    private func save(_ status: MailRecipient.Status) {
        var changed = person
        changed.subject = String(subject.replacingOccurrences(of: "\n", with: " ").prefix(300))
        changed.body = String(text.prefix(20_000))
        changed.status = changed.body.isEmpty && status == .approved ? .written : status
        Task { await model.update(changed) }
    }
}

/// Files that go with every mail, with a word on what they do to deliverability.
private struct AttachmentsRow: View {
    @Environment(AppModel.self) private var model
    let campaign: MailCampaign
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(campaign.attachments, id: \.self) { file in
                    HStack(spacing: 6) {
                        Image(systemName: file.type.hasPrefix("image/") ? "photo" : "doc.richtext").accessibilityHidden(true)
                        Text(file.name).lineLimit(1)
                        Text(file.size.formatted(.byteCount(style: .file))).foregroundStyle(.secondary)
                        Button("Remove \(file.name)", systemImage: "xmark.circle.fill") { Task { await model.removeAttachment(file, from: campaign) } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.background.secondary, in: .capsule)
                }
                if campaign.attachments.count < MailAttachment.countLimit {
                    let fromSpace = campaign.spaceID.map { model.spaceFiles($0).filter { !campaign.attachments.contains($0) } } ?? []
                    if fromSpace.isEmpty {
                        Button(campaign.attachments.isEmpty ? "Attach Files…" : "Add", systemImage: "paperclip") { picking = true }
                            .disabled(model.bulkWorking != nil)
                            .help("A portfolio, a deck or pictures that go with every mail. PDF, pictures, PowerPoint or Word; 15 MB together.")
                    } else {
                        Menu(campaign.attachments.isEmpty ? "Attach Files" : "Add", systemImage: "paperclip") {
                            Section("From the Space") {
                                ForEach(fromSpace, id: \.self) { file in Button(file.name) { Task { await model.attachExisting(file, to: campaign) } } }
                            }
                            Button("From Your Mac…") { picking = true }
                        }
                        .fixedSize().disabled(model.bulkWorking != nil)
                    }
                }
            }
            if !campaign.attachments.isEmpty {
                Text("Every mail gets these files. For people you haven't mailed before, attachments make spam filters stricter; a link to the file is safer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: MailAttachment.types.keys.compactMap { UTType(filenameExtension: $0) },
                      allowsMultipleSelection: true) { result in
            guard let files = try? result.get(), !files.isEmpty else { return }
            Task { await model.attach(files, to: campaign) }
        }
    }
}

/// Before a batch goes out: how many, from where, how fast, and Touch ID to approve exactly these mails.
private struct SendBulkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let campaign: MailCampaign
    let count: Int
    @State private var limit = 20
    @State private var problem: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send \(count) mails?").font(.title2.bold())
            Text("From your \(EmailMessage.accountName(campaign.account)) account, exactly as you approved them. Each person gets their own mail.")
                .foregroundStyle(.secondary)
            Stepper("Up to \(limit) a day", value: $limit, in: 5...100, step: 5)
            Label("One every 5 minutes, between 8:00 and 20:00. About \(MailCampaign.sendingDays(count, dailyLimit: limit)) day\(MailCampaign.sendingDays(count, dailyLimit: limit) == 1 ? "" : "s") for all of them.",
                  systemImage: "clock")
            Label("Blink pauses by itself if your mail provider asks it to slow down, and skips anyone who replies.", systemImage: "hand.raised")
            Label("Pause any time, or skip a single mail to take it out.", systemImage: "pause.circle")
            if let problem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    working = true
                    Task {
                        problem = await model.sendBulk(campaign, dailyLimit: limit)
                        working = false
                        if problem == nil { dismiss() }
                    }
                } label: { Label("Approve and Send", systemImage: "touchid") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(working || count == 0)
            }
        }
        .font(.callout)
        .padding(24)
        .frame(width: 460)
        .onAppear { limit = min(max(campaign.dailyLimit, 5), 100) }
    }
}

/// The mail as the person will get it: who it's from and to, the subject, the text set like a mail, and the files as
/// cards, so reviewing feels like reading the real thing, not a draft in a text box.
private struct MailPreview: View {
    let to: MailRecipient
    let from: MailCampaign
    let subject: String
    let text: String
    let files: [MailAttachment]
    let edit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SenderAvatar(name: to.name.isEmpty ? to.email : to.name, key: to.email, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("To:").foregroundStyle(.secondary)
                        Text(to.name.isEmpty ? to.email : to.name).fontWeight(.semibold)
                        if !to.name.isEmpty { Text(to.email).foregroundStyle(.secondary) }
                    }
                    .font(.callout).lineLimit(1)
                    Text("From: you, via \(EmailMessage.accountName(from.account))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let edit {
                    Button("Edit", systemImage: "pencil", action: edit).buttonStyle(.borderless).help("Change the subject or text")
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text(subject.isEmpty ? "(No subject)" : subject).font(.title3.weight(.semibold)).textSelection(.enabled)
                Text(text).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if !files.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(files, id: \.self) { file in
                            HStack(spacing: 10) {
                                Image(systemName: file.type.hasPrefix("image/") ? "photo.fill" : file.type == "application/pdf" ? "doc.richtext.fill" : "doc.fill")
                                    .font(.title2).foregroundStyle(file.type == "application/pdf" ? .red : .accentColor).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.name).font(.callout.weight(.medium)).lineLimit(1)
                                    Text(file.size.formatted(.byteCount(style: .file))).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                            .frame(maxWidth: 240, alignment: .leading)
                        }
                    }
                }
            }
            .padding(22)
        }
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mail to \(to.name.isEmpty ? to.email : to.name)")
    }
}

/// What Blink read on their company's website/// What Blink read on their company's website, with the page it came from, so the owner can check the mail's details.
private struct ResearchCardView: View {
    let card: ResearchCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("From their website", systemImage: "globe").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let summary = card.summary, !summary.isEmpty { Text(summary).font(.callout) }
            ForEach(card.facts ?? [], id: \.self) { Text("· \($0)").font(.callout).foregroundStyle(.secondary) }
            if let source = card.source, let url = URL(string: source), url.scheme == "https" {
                Link(url.host() ?? source, destination: url).font(.caption)
            }
        }
        .textSelection(.enabled)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: .rect(cornerRadius: 8))
    }
}

private struct AddContactsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let campaign: MailCampaign
    let done: ([String]) -> Void
    @State private var contacts = ""
    @State private var importing = false
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Contacts").font(.headline)
            TextEditor(text: $contacts).font(.body.monospaced()).frame(minHeight: 200).accessibilityLabel("Contacts")
            Text("One per line (Ana Silva <ana@studio.com>), or a CSV with an email column.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Import CSV…") { importing = true }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    working = true
                    Task { done(await model.addContacts(contacts, to: campaign)); working = false; dismiss() }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(working || contacts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .tabSeparatedText]) { result in
            guard let file = try? result.get() else { return }
            let access = file.startAccessingSecurityScopedResource()
            defer { if access { file.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: file, encoding: .utf8) { contacts = String(text.prefix(2_000_000)) }
        }
    }
}
#endif
