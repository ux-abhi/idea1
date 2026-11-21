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
                    }
                }
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
        .sheet(isPresented: $creating) { NewCampaignSheet(space: nil, table: nil) { selected = $0 } }
    }

    private func summary(_ campaign: MailCampaign) -> String {
        let people = model.bulkRecipients[campaign.id]
        guard let people else { return EmailMessage.accountName(campaign.account) }
        let drafts = people.filter { $0.status == .inDrafts }.count
        return "\(people.count) people" + (drafts > 0 ? " · \(drafts) in Drafts" : "")
    }
}

/// The batch's description, the mailbox it comes from, and the contacts.
/// A new bulk mail, from a pasted list or a Space's table. Opened from a table, it starts with that table and the
/// Space's own words as "What it's about".
struct NewCampaignSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let space: Space?
    let table: SpaceBlock?
    let created: (String) -> Void
    @State private var source = ""      // "" for a pasted list, else a table block's id
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
            Form {
                TextField("Name", text: $title, prompt: Text("Portfolio outreach, spring"))
                Section("What it's about") {
                    TextEditor(text: $context).frame(minHeight: 90).accessibilityLabel("What it's about")
                    Text("Who you are, why you're writing, and any facts or links the mails may use. Mails only state what's here or in each contact's row.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("What you want back", text: $goal, prompt: Text("A short call, a reply, feedback"))
                    TextField("Tone", text: $tone, prompt: Text("Your usual voice"))
                    Picker("Send from", selection: $account) {
                        ForEach(model.mailAccounts, id: \.self) { Text(EmailMessage.accountName($0)).tag($0) }
                    }
                    Toggle(isOn: $research) {
                        Text("Read each company's website")
                        Text("For a personal detail in each mail. Blink reads their home and about pages, once per company.")
                    }
                }
                Section("Contacts") {
                    Picker("From", selection: $source) {
                        Text("A list I paste").tag("")
                        ForEach(tables, id: \.block.id) { item in Text("\(item.space.title) table").tag(item.block.id) }
                    }
                    if let chosen {
                        let rows = model.tableRows[chosen.block.id] ?? []
                        let tags = SpaceTable.allTags(columns: chosen.block.data.columns ?? [], rows: rows)
                        Picker("Who", selection: $tag) {
                            Text("Everyone in the table").tag("")
                            ForEach(tags, id: \.self) { Text("Rows tagged #\($0)").tag($0) }
                        }
                        let count = SpaceTable.contacts(columns: chosen.block.data.columns ?? [], rows: rows, tag: tag).contacts.count
                        Text("\(count) people with an email address. Every other column can be used in the mails, and each row shows the mail's status.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        TextEditor(text: $contacts).font(.body.monospaced()).frame(minHeight: 110).accessibilityLabel("Contacts")
                        HStack {
                            Text("One per line (Ana Silva <ana@studio.com>), or a CSV with an email column. Every column can be used in the mails.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Import CSV…") { importing = true }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            if model.mailAccounts.isEmpty {
                Label("Connect a mailbox in Settings › Connections first.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding(.horizontal, 20)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(working || title.trimmingCharacters(in: .whitespaces).isEmpty || account.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 560, height: 640)
        .onAppear { account = model.mailAccounts.first ?? "" }
        .task {
            // Every Space's tables, so a bulk mail can start from any of them; opened from a table, that one.
            for space in model.spaces where model.spaceBlocks[space.id] == nil { await model.loadBlocks(space) }
            for item in tables where model.tableRows[item.block.id] == nil { await model.loadRows(item.block) }
            if let table { source = table.id }
        }
        .onChange(of: source) {
            tag = ""
            // The Space's own words as a start for "What it's about"; never over what the owner wrote.
            if let chosen, context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { context = model.spaceContext(chosen.space) }
            if let chosen, title.isEmpty { title = chosen.space.title }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .tabSeparatedText]) { result in
            guard let file = try? result.get() else { return }
            let access = file.startAccessingSecurityScopedResource()
            defer { if access { file.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: file, encoding: .utf8) { contacts = String(text.prefix(2_000_000)) }
        }
    }

    /// Table blocks with an email column, in every Space.
    private var tables: [(space: Space, block: SpaceBlock)] {
        model.spaces.flatMap { space in
            (model.spaceBlocks[space.id] ?? []).filter { $0.kind == .table && ($0.data.columns ?? []).contains { $0.kind == .email } }.map { (space, $0) }
        }
    }

    private var chosen: (space: Space, block: SpaceBlock)? { tables.first { $0.block.id == source } }

    private func create() {
        working = true
        var campaign = MailCampaign(title: String(title.trimmingCharacters(in: .whitespaces).prefix(200)), context: String(context.prefix(8000)),
                                    goal: String(goal.prefix(1000)), tone: String(tone.prefix(500)), account: account, research: research)
        if let chosen { (campaign.spaceID, campaign.tableBlock, campaign.tag) = (chosen.space.id, chosen.block.id, tag) }
        Task {
            defer { working = false }
            guard await model.newCampaign(campaign) else { return }
            let problems = chosen != nil ? await model.importFromTable(campaign) : contacts.isEmpty ? [] : await model.addContacts(contacts, to: campaign)
            UserDefaults.standard.set(problems, forKey: "bulk.problems.\(campaign.id)")
            created(campaign.id)
            dismiss()
            if space != nil { // made from a Space's table: go to it in Bulk Mail
                UserDefaults.standard.set(true, forKey: "inbox.bulk")
                UserDefaults.standard.set(campaign.id, forKey: "bulk.selected")
                model.openPage = "inbox"
            }
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
                    }
                }
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
            Label("When you send from Apple Mail, send a few at a time. Dozens at once can get your account limited: keep it to about 20–50 a day at first.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .task {
            await model.loadRecipients(campaign)
            problems = UserDefaults.standard.stringArray(forKey: "bulk.problems.\(campaign.id)") ?? []
        }
        .task(id: people.map { "\($0.id)\($0.subject.count)\($0.body.count)\($0.status.rawValue)" }) {
            let mails = people.filter { $0.status == .written || $0.status == .approved }.map { (id: $0.id, subject: $0.subject, body: $0.body) }
            warnings = await Task.detached { MailLint.batch(mails) }.value
        }
        .sheet(isPresented: $adding) { AddContactsSheet(campaign: campaign) { problems = $0 } }
        .confirmationDialog("Delete “\(campaign.title)”?", isPresented: $confirmDelete) {
            Button("Delete Bulk Mail", role: .destructive) { Task { await model.delete(campaign) } }
        } message: {
            Text("Its contacts and mails are deleted from Blink. Drafts already in your mailbox stay there.")
        }
    }

    /// The next step, as one row of buttons: samples first, then the rest, then approve and save to Drafts.
    @ViewBuilder
    private func steps(fresh: [MailRecipient], written: [MailRecipient], approved: [MailRecipient]) -> some View {
        let done = people.count - fresh.count
        HStack(spacing: 10) {
            if let working = model.bulkWorking {
                ProgressView().controlSize(.small)
                Text(working).foregroundStyle(.secondary)
            } else if people.isEmpty {
                Button("Add Contacts…") { adding = true }.buttonStyle(.borderedProminent)
            } else if done == 0 {
                Button("Write 3 Samples") { Task { await model.writeMails(fresh.prefix(3).map(\.id), in: campaign) } }
                    .buttonStyle(.borderedProminent)
                Text("Check the style on a few before Blink writes all \(people.count).").foregroundStyle(.secondary)
            } else {
                TextField("Style note, e.g. shorter, less formal", text: $note).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                if !fresh.isEmpty {
                    Button("Write the Rest (\(fresh.count))") { Task { await model.writeMails(fresh.map(\.id), in: campaign, note: note) } }
                        .buttonStyle(.borderedProminent)
                }
                if !written.isEmpty {
                    Button("Rewrite \(written.count) with Note") { Task { await model.writeMails(written.map(\.id), in: campaign, note: note) } }
                        .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                    let clean = written.filter { (warnings[$0.id] ?? []).isEmpty && !$0.flags.contains("mailed_recently") }
                    Button("Approve \(clean.count) Without Warnings") {
                        Task { for var person in clean { person.status = .approved; await model.update(person) } }
                    }
                    .disabled(clean.isEmpty)
                }
                Spacer()
                if !approved.isEmpty {
                    Button("Save \(approved.count) to Drafts", systemImage: "tray.and.arrow.down") { Task { await model.saveBulkDrafts(campaign) } }
                        .buttonStyle(.borderedProminent)
                        .help("Puts the approved mails in your Drafts folder. Nothing is sent.")
                }
            }
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

    private var locked: Bool { [.inDrafts, .sent, .replied, .bounced].contains(person.status) }

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
                    Button("Write This Mail") { Task { await model.writeMails([person.id], in: campaign) } }.disabled(model.bulkWorking != nil)
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
