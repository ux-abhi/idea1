// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Money, laid out like a wallet: your accounts as cards, where this month's money went as small tiles, and the
/// latest spends; on the right, this month's total with its pace against last month, and how much of your limits is
/// used. Spending is typed in the bar at the bottom; Blink sorts it and you check it here before it's saved.
struct MoneyView: View {
    @Environment(AppModel.self) private var model
    @State private var editingLimit: SpendCategory?
    @State private var editingAccount: AccountEditor.Mode?

    private var month: String { MoneyMath.month(of: HabitDay.key(.now)) }

    var body: some View {
        let today = HabitDay.key(.now)
        let summary = MoneyMath.summary(model.spends, today: today)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Money").font(.system(.largeTitle, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
                    Text(pageSummary(summary)).foregroundStyle(.secondary)
                }
                if let problem = model.moneyProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if !model.spendDrafts.isEmpty { drafts }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        leftColumn(summary).frame(minWidth: 460)
                        rightColumn(summary, today: today).frame(width: 340)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        rightColumn(summary, today: today)
                        leftColumn(summary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(BlinkCanvas())
        .animation(.default, value: model.spends)
        .task { await model.loadMoney() }
        .sheet(item: $editingLimit) { LimitEditor(category: $0) }
        .sheet(item: $editingAccount) { AccountEditor(mode: $0) }
    }

    private func leftColumn(_ s: MoneyMath.Summary) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Accounts", trailing: model.accounts.count > 1
                    ? "\(MoneyMath.totalBalance(model.accounts).formatted(.currency(code: MoneyMath.currency))) in total" : nil)
            AccountCards(editing: $editingAccount)
            section("Where it went this month")
            if MoneyMath.totals(model.spends, month: month).isEmpty {
                Text("Nothing spent yet this month. Type what you spend in the bar below.").foregroundStyle(.secondary)
            }
            categoryTiles
            section("Recent spending")
            latest
            ApplePayCard()
        }
    }

    private func rightColumn(_ s: MoneyMath.Summary, today: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            spentCard(s, today: today)
            if let limits = limitsTotal { limitsCard(spent: s.total, limits: limits) }
            else if !model.accounts.isEmpty { leftCard(s, today: today) }
        }
    }

    private func section(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let trailing { Text(trailing).foregroundStyle(.secondary).monospacedDigit() }
        }
    }

    private func pageSummary(_ s: MoneyMath.Summary) -> String {
        guard let change = s.change else { return "\(s.total.formatted(.currency(code: MoneyMath.currency))) this month" }
        let pct = Int((abs(change) * 100).rounded())
        return "\(s.total.formatted(.currency(code: MoneyMath.currency))) this month · \(pct)% \(change >= 0 ? "more" : "less") than last month by today"
    }

    private var limitsTotal: Decimal? {
        model.budgets.isEmpty ? nil : model.budgets.reduce(Decimal.zero) { $0 + $1.monthlyLimit }
    }

    // MARK: Right column

    /// This month's total, how it compares, and its pace drawn against last month.
    private func spentCard(_ s: MoneyMath.Summary, today: String) -> some View {
        let day = Int(today.suffix(2)) ?? 1
        let daily = Array(MoneyMath.daily(model.spends, month: month).prefix(day))
        return VStack(spacing: 6) {
            Text("Spent this month").font(.callout).foregroundStyle(.secondary)
            Text(s.total, format: .currency(code: MoneyMath.currency))
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                .contentTransition(.numericText())
            if let change = s.change {
                let pct = Int((abs(change) * 100).rounded())
                Text("\(change >= 0 ? "▲" : "▼") \(pct)% vs last month by today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(change > 0.1 ? Color.orange : change < 0 ? .green : .secondary)
            }
            if s.total > 0 || s.lastMonthTotal > 0 {
                PaceChart(thisMonth: MoneyMath.cumulative(daily),
                          lastMonth: MoneyMath.cumulative(MoneyMath.daily(model.spends, month: MoneyMath.previous(month: month))),
                          limit: limitsTotal, daysInMonth: MoneyMath.daysIn(month: month))
                    .padding(.top, 8)
                Text("Solid: this month · Dashed: last month").font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("Your pace shows after your first spend.").font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: Tokens.Radius.card)
    }

    /// Of all your monthly limits together, how much is used: a dark card with a ring, like a plan's progress.
    private func limitsCard(spent: Decimal, limits: Decimal) -> some View {
        let used = MoneyMath.used(spent, of: limits)
        return darkCard(caption: "Your limits", title: used >= 1 ? "Over the limit" : "\((limits - spent).formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0)))) left",
                        progress: min(used, 1), label: "\(Int((used * 100).rounded()))%", tint: used >= 1 ? .red : used >= 0.8 ? .orange : .white)
    }

    /// With accounts and no limits: what's left at month end at this pace.
    private func leftCard(_ s: MoneyMath.Summary, today: String) -> some View {
        let total = MoneyMath.totalBalance(model.accounts)
        let left = MoneyMath.leftAtMonthEnd(total: total, summary: s, today: today)
        let runway = MoneyMath.runwayDays(total: total, average: s.average)
        let share = total > 0 ? min(max(NSDecimalNumber(decimal: left / total).doubleValue, 0), 1) : 0
        return darkCard(caption: runway.map { "Left at month end · lasts \($0 >= 365 ? "over a year" : "\($0) days")" } ?? "Left at month end",
                        title: left.formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0))),
                        progress: share, label: "\(Int((share * 100).rounded()))%", tint: left < 0 ? .red : .white)
    }

    private func darkCard(caption: String, title: String, progress: Double, label: String, tint: Color) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(caption).font(.callout).foregroundStyle(.white.opacity(0.6))
                Text(title).font(.title2.weight(.semibold)).foregroundStyle(.white).monospacedDigit()
            }
            Spacer()
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 9)
                Circle().trim(from: 0, to: progress).stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(label).font(.callout.weight(.bold)).foregroundStyle(.white).monospacedDigit()
            }
            .frame(width: 70, height: 70)
            .accessibilityHidden(true)
        }
        .padding(20)
        .background { HorizonGlow() }
        .clipShape(.rect(cornerRadius: Tokens.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Where it went

    /// This month's categories as small tiles, biggest first, each against its limit; one more tile sets a limit.
    private var categoryTiles: some View {
        let totals = MoneyMath.totals(model.spends, month: month)
        let limited = model.budgets.filter { b in !totals.contains { $0.category == b.category } }.map { (category: $0.category, total: Decimal.zero) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            ForEach(totals + limited, id: \.category) { row in
                CategoryTile(category: row.category, total: row.total,
                             limit: model.budgets.first { $0.category == row.category }?.monthlyLimit) { editingLimit = row.category }
            }
            Menu {
                ForEach(SpendCategory.allCases) { c in Button(c.title, systemImage: c.symbol) { editingLimit = c } }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus").font(.title3.weight(.semibold))
                    Text("Set a Limit").font(.callout.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 128)
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.tile, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    // MARK: Entry: type → AI sorts → check → save

    /// Spending typed in the bar, sorted by Blink: check, fix and save, or discard.
    private var drafts: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            Text("Check before saving").font(.headline)
            ForEach($model.spendDrafts) { $draft in
                DraftRow(draft: $draft) { model.spendDrafts.removeAll { $0.id == draft.id } }
            }
            HStack {
                Text("Total \(model.spendDrafts.reduce(Decimal.zero) { $0 + $1.amount }.formatted(.currency(code: MoneyMath.currency)))").font(.headline)
                Spacer()
                Button("Discard") { model.spendDrafts = [] }
                Button("Save \(model.spendDrafts.count == 1 ? "Spend" : "All \(model.spendDrafts.count)")") {
                    let saving = model.spendDrafts
                    Task { if await model.addSpends(saving) != nil { model.spendDrafts = [] } }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.spendDrafts.contains { $0.amount <= 0 })
            }
        }
        .padding(16)
        .cardSurface(radius: Tokens.Radius.tile)
    }

    // MARK: Recent spending

    /// The latest spends as one list: what, the day, the amount, and a menu to change or delete each.
    private var latest: some View {
        let recent = Array(model.spends.prefix(30))
        return VStack(spacing: 0) {
            if recent.isEmpty {
                Text("Spends you add show here.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, spend in
                if index > 0 { Divider().padding(.leading, 60) }
                SpendRow(spend: spend).padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .cardSurface(radius: Tokens.Radius.tile)
    }
}

/// One category this month: its icon on a dark tile, the amount, and the bar against its limit when there is one.
private struct CategoryTile: View {
    let category: SpendCategory
    let total: Decimal
    let limit: Decimal?
    let edit: () -> Void

    var body: some View {
        let used = limit.map { MoneyMath.used(total, of: $0) } ?? 0
        Button(action: edit) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: category.symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black, in: .rect(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                Text(category.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(total, format: .currency(code: MoneyMath.currency).precision(.fractionLength(0)))
                    .font(.title3.weight(.bold)).monospacedDigit()
                if let limit {
                    ProgressView(value: min(used, 1))
                        .tint(used >= 1 ? .red : used >= 0.8 ? .orange : .accentColor)
                    Text("of \(limit.formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0))))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .cardSurface(radius: Tokens.Radius.tile)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Set the monthly limit")
    }
}

/// The accounts as cards in a row, like the cards in a wallet: kind, balance big, name. A click updates the balance;
/// the last card adds an account.
private struct AccountCards: View {
    @Environment(AppModel.self) private var model
    @Binding var editing: AccountEditor.Mode?
    @State private var deleting: MoneyAccount?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(model.accounts) { account in
                    Button { editing = .balance(account) } label: { card(account) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Update Balance…", systemImage: "pencil") { editing = .balance(account) }
                            if !account.isDefault {
                                Button("Make Default", systemImage: "star") { Task { await model.makeDefault(account) } }
                            }
                            Button("Delete Account…", systemImage: "trash", role: .destructive) { deleting = account }
                        }
                        .accessibilityHint("Update the balance")
                }
                Button { editing = .new } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.title2.weight(.semibold))
                        Text(model.accounts.isEmpty ? "Add your first account" : "Add Account").font(.callout.weight(.medium))
                        if model.accounts.isEmpty {
                            Text("Bank, savings, cash or card, with today's balance").font(.caption).multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(width: 200, height: 140)
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
        .confirmationDialog("Delete \(deleting?.name ?? "this account")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Account", role: .destructive) { if let account = deleting { Task { await model.deleteAccount(account) } } }
        } message: {
            Text("Its balance goes. Spending you added stays, without an account.")
        }
    }

    private func card(_ account: MoneyAccount) -> some View {
        let now = MoneyMath.balance(of: account)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: account.kind.symbol).font(.title3)
                Spacer()
                if account.isDefault {
                    Text("Default").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.white.opacity(0.18), in: .capsule)
                }
            }
            Spacer()
            Text(now, format: .currency(code: MoneyMath.currency))
                .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                .foregroundStyle(now < 0 ? Color.red : .white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(account.name) · \(account.kind.title)").font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 240, height: 140)
        .background { HorizonGlow(tint: tint(account.kind)) }
        .clipShape(.rect(cornerRadius: Tokens.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.name), \(now.formatted(.currency(code: MoneyMath.currency)))\(account.isDefault ? ", default" : "")")
    }

    /// One soft colour per kind of account, rising from the bottom of the black card.
    private func tint(_ kind: MoneyAccount.Kind) -> Color {
        switch kind {
        case .checking: .blue
        case .savings: .green
        case .cash: .orange
        case .card: .indigo
        case .other: .gray
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
        HStack(spacing: 12) {
            Image(systemName: spend.category.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(spend.note.isEmpty ? spend.category.title : spend.note).font(.callout.weight(.medium)).lineLimit(1)
                Text("\(spend.category.title) · \(HabitDay.date(fromKey: spend.spentOn).map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? spend.spentOn)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(spend.amount, format: .currency(code: MoneyMath.currency)).font(.callout.weight(.semibold)).monospacedDigit()
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
