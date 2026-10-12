// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Money (Phase 7, first slice): type the day's spending, the AI sorts it, you check and save. This month per category
/// against its limit, and the latest spends to fix or delete.
struct MoneyView: View {
    @Environment(AppModel.self) private var model
    @State private var typed = ""
    @State private var drafts: [SpendDraft] = []
    @State private var editingLimit: SpendCategory?

    private var month: String { MoneyMath.month(of: HabitDay.key(.now)) }

    var body: some View {
        let total = MoneyMath.total(model.spends, month: month)
        DashPage("Money", summary: "\(total.formatted(.currency(code: "EUR"))) this month") {
            if let problem = model.moneyProblem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            DashCard("Add spending") { entry }
            DashCard("This month") { monthCard }
            DashCard("Latest") { latest }
        }
        .task { await model.loadMoney() }
        .sheet(item: $editingLimit) { LimitEditor(category: $0) }
    }

    // MARK: Entry: type → AI sorts → check → save

    @ViewBuilder
    private var entry: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("What did you spend today? e.g. lunch 8.50, rewe 23.40, bus 3, yesterday cinema 12",
                      text: $typed, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
                .onSubmit(sort)
            HStack {
                Button(action: sort) {
                    if model.sortingSpends { ProgressView().controlSize(.small) } else { Text("Sort It") }
                }
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || model.sortingSpends)
                Text("Blink reads the amounts and picks a category. You check before saving.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !drafts.isEmpty {
                Divider()
                ForEach($drafts) { $draft in DraftRow(draft: $draft) { drafts.removeAll { $0.id == draft.id } } }
                HStack {
                    Text("Total \(drafts.reduce(Decimal.zero) { $0 + $1.amount }.formatted(.currency(code: "EUR")))").font(.headline)
                    Spacer()
                    Button("Discard") { drafts = [] }
                    Button("Save \(drafts.count == 1 ? "Spend" : "All \(drafts.count)")") {
                        Task {
                            if await model.addSpends(drafts) != nil { drafts = []; typed = "" }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(drafts.contains { $0.amount <= 0 })
                }
            }
        }
    }

    private func sort() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.sortingSpends else { return }
        Task { drafts = await model.sortSpends(text) }
    }

    // MARK: This month per category, against its limit

    @ViewBuilder
    private var monthCard: some View {
        let totals = MoneyMath.totals(model.spends, month: month)
        let limited = model.budgets.filter { b in !totals.contains { $0.category == b.category } }
        if totals.isEmpty && limited.isEmpty {
            Text("Nothing spent this month yet.").foregroundStyle(.secondary)
        }
        ForEach(totals, id: \.category) { row in categoryRow(row.category, total: row.total) }
        ForEach(limited, id: \.category) { categoryRow($0.category, total: 0) }
        Menu("Set a Limit") {
            ForEach(SpendCategory.allCases) { c in Button(c.title, systemImage: c.symbol) { editingLimit = c } }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.top, 4)
    }

    private func categoryRow(_ category: SpendCategory, total: Decimal) -> some View {
        let limit = model.budgets.first { $0.category == category }?.monthlyLimit
        let used = limit.map { MoneyMath.used(total, of: $0) } ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(category.title, systemImage: category.symbol)
                Spacer()
                Text(total, format: .currency(code: "EUR")).monospacedDigit()
                if let limit {
                    Text("of \(limit.formatted(.currency(code: "EUR")))").foregroundStyle(.secondary)
                }
            }
            if limit != nil {
                ProgressView(value: min(used, 1))
                    .tint(used >= 1 ? .red : used >= 0.8 ? .orange : .accentColor)
                    .accessibilityValue(used >= 1 ? "Over the limit" : "\(Int(used * 100)) percent of the limit")
            }
        }
        .contentShape(.rect)
        .onTapGesture { editingLimit = category }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Set the monthly limit")
    }

    // MARK: Latest spends, by day

    @ViewBuilder
    private var latest: some View {
        let recent = Array(model.spends.prefix(40))
        if recent.isEmpty {
            Text("Spends you add show here.").foregroundStyle(.secondary)
        }
        let days = Dictionary(grouping: recent, by: \.spentOn).sorted { $0.key > $1.key }
        ForEach(days, id: \.key) { day, list in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(HabitDay.date(fromKey: day).map { $0.formatted(.dateTime.weekday(.wide).day().month()) } ?? day)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(list.reduce(Decimal.zero) { $0 + $1.amount }, format: .currency(code: "EUR"))
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                ForEach(list) { SpendRow(spend: $0) }
            }
            .padding(.bottom, 6)
        }
    }
}

/// One sorted entry before saving: amount, what, category, all editable.
private struct DraftRow: View {
    @Binding var draft: SpendDraft
    let remove: () -> Void
    // Text, not a number field: a macOS number field only commits on Return, so a click on Save would keep the old amount.
    @State private var amount = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("Amount", text: $amount)
                .textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.trailing)
                .onAppear { amount = draft.amount.formatted(.number.precision(.fractionLength(2))) }
                .onChange(of: amount) { draft.amount = MoneyMath.parseAmount(amount) ?? 0 }
            TextField("What", text: $draft.note).textFieldStyle(.roundedBorder)
            Picker("Category", selection: $draft.category) {
                ForEach(SpendCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .labelsHidden().frame(width: 150)
            Text(HabitDay.date(fromKey: draft.spentOn).map { $0.formatted(.dateTime.weekday(.abbreviated).day()) } ?? draft.spentOn)
                .font(.caption).foregroundStyle(.secondary).frame(width: 50)
            Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
        }
    }
}

/// A saved spend: change its category from the menu, or delete it.
private struct SpendRow: View {
    @Environment(AppModel.self) private var model
    let spend: Spend

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: spend.category.symbol).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
            Text(spend.note.isEmpty ? spend.category.title : spend.note).lineLimit(1)
            Spacer()
            Text(spend.amount, format: .currency(code: "EUR")).monospacedDigit()
            Menu("Change", systemImage: "ellipsis.circle") { menu }
                .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spend.note), \(spend.category.title), \(spend.amount.formatted(.currency(code: "EUR")))")
    }

    @ViewBuilder
    private var menu: some View {
        Menu("Category") {
            ForEach(SpendCategory.allCases) { c in
                Button(c.title, systemImage: c.symbol) {
                    var changed = spend
                    changed.category = c
                    Task { await model.saveSpend(changed) }
                }
            }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.deleteSpend(spend) } }
    }
}

/// Sets a category's monthly limit (empty removes it).
private struct LimitEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let category: SpendCategory
    @State private var limit = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(category.title): monthly limit", systemImage: category.symbol).font(.headline)
            TextField("e.g. 200", text: $limit)
                .textFieldStyle(.roundedBorder).frame(width: 220)
                .onAppear { limit = model.budgets.first { $0.category == category }.map { "\($0.monthlyLimit)" } ?? "" }
            Text("The bar turns orange at 80% and red when you go over. Leave it empty for no limit.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Save") {
                    Task {
                        await model.setLimit(MoneyMath.parseAmount(limit), for: category)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(!limit.trimmingCharacters(in: .whitespaces).isEmpty && MoneyMath.parseAmount(limit) == nil)
            }
        }
        .padding(14)
    }
}
#endif
