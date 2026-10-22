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
    @State private var editingAccount: AccountEditor.Mode?

    private var month: String { MoneyMath.month(of: HabitDay.key(.now)) }

    var body: some View {
        let today = HabitDay.key(.now)
        let summary = MoneyMath.summary(model.spends, today: today)
        DashPage("Money", summary: pageSummary(summary)) {
            if let problem = model.moneyProblem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            DashCard("Add spending") { entry }
            metrics(summary, today: today)
            charts(summary, today: today)
            DashCard("Categories and limits") { monthCard }
            DashCard("Latest") { latest }
            AccountsCard(editing: $editingAccount)
            ApplePayCard()
        }
        .animation(.default, value: model.spends)
        .task { await model.loadMoney() }
        .sheet(item: $editingLimit) { LimitEditor(category: $0) }
        .sheet(item: $editingAccount) { AccountEditor(mode: $0) }
    }

    /// The headline numbers in one row: what you have, this month, where the month lands, and how long the money lasts.
    private func metrics(_ s: MoneyMath.Summary, today: String) -> some View {
        let change = s.change.map { c -> (String, Color) in
            let pct = Int((abs(c) * 100).rounded())
            return (c >= 0 ? "▲ \(pct)% vs last month" : "▼ \(pct)% vs last month", c > 0.1 ? .orange : c < 0 ? .green : .secondary)
        }
        let total = MoneyMath.totalBalance(model.accounts)
        let left = MoneyMath.leftAtMonthEnd(total: total, summary: s, today: today)
        let runway = MoneyMath.runwayDays(total: total, average: s.average)
        let overForecast = limitsTotal.map { s.forecast > $0 } ?? false
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            if !model.accounts.isEmpty {
                MetricTile(title: "Money you have", value: total, detail: "\(model.accounts.count) account\(model.accounts.count == 1 ? "" : "s")",
                           valueColor: total < 0 ? .red : .primary)
            }
            MetricTile(title: "This month", value: s.total, detail: change?.0 ?? "No data last month",
                       detailColor: change?.1 ?? .secondary)
            if model.accounts.isEmpty {
                MetricTile(title: "Month-end forecast", value: s.forecast,
                           detail: limitsTotal.map { overForecast ? "Over your limits (\($0.formatted(.currency(code: MoneyMath.currency))))" : "Within your limits" }
                               ?? "At this pace", detailColor: overForecast ? .red : .secondary)
            } else {
                MetricTile(title: "Left at month end", value: left, detail: "If you keep this pace",
                           detailColor: left < 0 ? .red : .secondary, valueColor: left < 0 ? .red : .primary)
                MetricTile(title: "Lasts", text: runway.map { $0 >= 365 ? "Over a year" : "\($0) days" } ?? "—",
                           detail: runway.map { _ in "At \(s.average.formatted(.currency(code: MoneyMath.currency))) a day" } ?? "Add spends to see",
                           valueColor: (runway ?? 99) < 30 ? .orange : .primary)
            }
        }
    }

    private func pageSummary(_ s: MoneyMath.Summary) -> String {
        guard let change = s.change else { return "\(s.total.formatted(.currency(code: MoneyMath.currency))) this month" }
        let pct = Int((abs(change) * 100).rounded())
        return "\(s.total.formatted(.currency(code: MoneyMath.currency))) this month · \(pct)% \(change >= 0 ? "more" : "less") than last month by today"
    }

    // MARK: Dashboard: headline numbers and charts

    private var limitsTotal: Decimal? {
        model.budgets.isEmpty ? nil : model.budgets.reduce(Decimal.zero) { $0 + $1.monthlyLimit }
    }

    @ViewBuilder
    private func charts(_ s: MoneyMath.Summary, today: String) -> some View {
        let day = Int(today.suffix(2)) ?? 1
        let daily = Array(MoneyMath.daily(model.spends, month: month).prefix(day))
        if s.total > 0 || s.lastMonthTotal > 0 {
            DashCard("Spending pace") {
                PaceChart(thisMonth: MoneyMath.cumulative(daily),
                          lastMonth: MoneyMath.cumulative(MoneyMath.daily(model.spends, month: MoneyMath.previous(month: month))),
                          limit: limitsTotal, daysInMonth: MoneyMath.daysIn(month: month))
                Text("Solid: this month · Dashed: last month")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if s.total == 0 && s.lastMonthTotal == 0 {
            EmptyCard(symbol: "chart.xyaxis.line", title: "Charts appear after your first spend",
                      message: "Your spending pace against last month, each day's total, and where the money goes by category.")
        }
        if s.total > 0 {
            HStack(alignment: .top, spacing: 16) {
                DashCard("Day by day") {
                    DailyBars(daily: daily, average: s.average, daysInMonth: MoneyMath.daysIn(month: month))
                }
                DashCard("By category") {
                    CategoryRing(totals: MoneyMath.totals(model.spends, month: month))
                }
            }
        }
    }

    // MARK: Entry: type → AI sorts → check → save

    @ViewBuilder
    private var entry: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("What did you spend? e.g. lunch 8.50, bus 3",
                      text: $typed, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
                .onSubmit(sort)
            HStack {
                Button(action: sort) {
                    if model.sortingSpends { ProgressView().controlSize(.small) } else { Text("Sort It") }
                }
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || model.sortingSpends)
                .help("Blink reads the amounts and picks a category; you check before saving")
            }
            if !drafts.isEmpty {
                Divider()
                ForEach($drafts) { $draft in DraftRow(draft: $draft) { drafts.removeAll { $0.id == draft.id } } }
                HStack {
                    Text("Total \(drafts.reduce(Decimal.zero) { $0 + $1.amount }.formatted(.currency(code: MoneyMath.currency)))").font(.headline)
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
        return Button { editingLimit = category } label: { VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(category.title, systemImage: category.symbol)
                Spacer()
                Text(total, format: .currency(code: MoneyMath.currency)).monospacedDigit()
                if let limit {
                    Text("of \(limit.formatted(.currency(code: MoneyMath.currency)))").foregroundStyle(.secondary)
                }
            }
            if limit != nil {
                ProgressView(value: min(used, 1))
                    .tint(used >= 1 ? .red : used >= 0.8 ? .orange : .accentColor)
                    .accessibilityValue(used >= 1 ? "Over the limit" : "\(Int(used * 100)) percent of the limit")
            }
        }
        .contentShape(.rect) }
        .buttonStyle(.plain)
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
                    Text(list.reduce(Decimal.zero) { $0 + $1.amount }, format: .currency(code: MoneyMath.currency))
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
    @Environment(AppModel.self) private var model
    @Binding var draft: SpendDraft
    private var accounts: [MoneyAccount] { model.accounts }
    let remove: () -> Void
    // Text, not a number field: a macOS number field only commits on Return, so a click on Save would keep the old amount.
    @State private var amount = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
            TextField("Amount", text: $amount)
                .textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.trailing)
                // No thousands separators: "1.250,40" would be ambiguous to read back.
                .onAppear { amount = draft.amount.formatted(.number.grouping(.never).precision(.fractionLength(2))) }
                .onChange(of: amount) { draft.amount = MoneyMath.parseAmount(amount) ?? 0 }
            TextField("What", text: $draft.note).textFieldStyle(.roundedBorder)
        }
        HStack(spacing: 8) {
            Picker("Category", selection: $draft.category) {
                ForEach(SpendCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .labelsHidden().frame(width: 150)
            if !accounts.isEmpty {
                Picker("Paid from", selection: $draft.accountID) {
                    Text("No account").tag(String?.none)
                    ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden().frame(width: 120)
            }
            Text(HabitDay.date(fromKey: draft.spentOn).map { $0.formatted(.dateTime.weekday(.abbreviated).day()) } ?? draft.spentOn)
                .font(.caption).foregroundStyle(.secondary).frame(width: 50)
            Spacer(minLength: 0)
            Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
        }
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
            Text(spend.amount, format: .currency(code: MoneyMath.currency)).monospacedDigit()
            Menu("Change", systemImage: "ellipsis.circle") { menu }
                .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spend.note), \(spend.category.title), \(spend.amount.formatted(.currency(code: MoneyMath.currency)))")
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
        if !model.accounts.isEmpty {
            Menu("Paid From") {
                ForEach(model.accounts) { a in
                    Button(a.name, systemImage: spend.accountID == a.id ? "checkmark" : a.kind.symbol) {
                        var changed = spend
                        changed.accountID = a.id
                        Task { await model.saveSpend(changed) }
                    }
                }
                Button("No Account") {
                    var changed = spend
                    changed.accountID = nil
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
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
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
