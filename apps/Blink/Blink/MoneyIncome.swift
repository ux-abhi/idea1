// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// What the income sheet is editing: something new, money that came in once, or a recurring income.
enum IncomeEditing: Identifiable {
    case new, entry(Income), plan(IncomePlan)
    var id: String {
        switch self {
        case .new: "new"
        case .entry(let e): e.id
        case .plan(let p): p.id
        }
    }
}

/// Money coming in for the month shown: what came in, what's left after spending, and the income that repeats.
struct IncomeCard: View {
    @Environment(AppModel.self) private var model
    /// The month on screen ("2026-11") and what was spent in it.
    let month: String
    let spent: Decimal
    @Binding var editing: IncomeEditing?

    var body: some View {
        let came = MoneyMath.received(model.income, month: month)
        let once = model.income.filter { $0.planID == nil && MoneyMath.month(of: $0.receivedOn) == month }
        let currency = Decimal.FormatStyle.Currency(code: MoneyMath.currency).precision(.fractionLength(0))
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Income").font(.headline)
                Spacer()
                if came > 0 { Text("+\(came.formatted(currency))").font(.headline).monospacedDigit().foregroundStyle(.green) }
            }
            if came > 0 || spent > 0 {
                let left = came - spent
                Text("\(came.formatted(currency)) in · \(spent.formatted(currency)) spent · \(left >= 0 ? "\(left.formatted(currency)) left over" : "\((-left).formatted(currency)) more out than in")")
                    .font(.callout).foregroundStyle(left >= 0 ? Color.secondary : .orange)
            }
            if model.incomePlans.isEmpty && once.isEmpty {
                Text("Salary, freelance work, rent from a lodger: add it once, or every month for as long as it runs.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.incomePlans) { plan in
                Button { editing = .plan(plan) } label: { planRow(plan) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit…", systemImage: "pencil") { editing = .plan(plan) }
                        Button(plan.paused ? "Resume" : "Pause", systemImage: plan.paused ? "play" : "pause") {
                            var changed = plan
                            changed.paused.toggle()
                            Task { await model.saveIncomePlan(changed) }
                        }
                        Button("Stop This Income", systemImage: "stop", role: .destructive) { Task { await model.deleteIncomePlan(plan) } }
                    }
            }
            ForEach(once) { entry in
                Button { editing = .entry(entry) } label: { entryRow(entry) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit…", systemImage: "pencil") { editing = .entry(entry) }
                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.deleteIncome(entry) } }
                    }
            }
            Button("Add Income", systemImage: "plus") { editing = .new }
                .buttonStyle(.borderless)
        }
        .padding(16)
        .cardSurface(radius: Tokens.Radius.tile)
    }

    private func planRow(_ plan: IncomePlan) -> some View {
        let today = MoneyMath.month(of: HabitDay.key(.now))
        let ended = plan.ended(by: today)
        return HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle").foregroundStyle(.green).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(plan.note).font(.callout.weight(.medium)).lineLimit(1)
                Text(ended ? "Ended \(IncomeEditor.monthWords(plan.endsMonth ?? ""))" : plan.paused ? "Paused"
                     : "Every month on the \(BillEditor.ordinal(plan.day))" + (plan.endsMonth.map { " · until \(IncomeEditor.monthWords($0))" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(plan.amount, format: .currency(code: MoneyMath.currency)).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .opacity(plan.paused || ended ? 0.5 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this income")
    }

    private func entryRow(_ entry: Income) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle").foregroundStyle(.green).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.note).font(.callout.weight(.medium)).lineLimit(1)
                Text(HabitDay.date(fromKey: entry.receivedOn)?.formatted(.dateTime.day().month(.abbreviated)) ?? entry.receivedOn)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.amount, format: .currency(code: MoneyMath.currency)).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this income")
    }
}

/// Adds or changes income: once (with the day it came in) or every month (a day, and for how long).
struct IncomeEditor: View {
    enum Often: Hashable { case once, monthly }
    /// How long a monthly income runs: a number of months, until a chosen month, or until stopped.
    enum Length: Hashable { case open, months(Int), until }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let editing: IncomeEditing
    @State private var note = ""
    @State private var amount = ""
    @State private var accountID: String?
    @State private var often = Often.once
    @State private var receivedOn = Date.now
    @State private var day = Calendar.current.component(.day, from: .now)
    @State private var length = Length.open
    @State private var untilMonth = Calendar.current.date(byAdding: .month, value: 5, to: .now) ?? .now
    @State private var countThisMonth = false
    @State private var saving = false

    private var today: String { HabitDay.key(.now) }
    private var isNew: Bool { if case .new = editing { true } else { false } }
    /// The first month a new monthly income comes in: this month if its day is still ahead or this month's is counted.
    private var firstMonth: String {
        let now = MoneyMath.month(of: today)
        let dayPassed = day <= (Int(today.suffix(2)) ?? 1)
        return !dayPassed || countThisMonth ? now : MoneyMath.next(month: now)
    }
    /// The last month it comes in, from the length picked (nil: until stopped).
    private var lastMonth: String? {
        switch length {
        case .open: nil
        case .months(let n): IncomePlan.lastMonth(startingWith: firstMonth, months: n)
        case .until: MoneyMath.month(of: HabitDay.key(untilMonth))
        }
    }

    var body: some View {
        Form {
            TextField("What", text: $note, prompt: Text("Salary, client payment, rent…"))
            TextField("Amount", text: $amount, prompt: Text("e.g. 3000"))
            if !model.accounts.isEmpty {
                Picker("Into", selection: $accountID) {
                    Text("No account").tag(String?.none)
                    ForEach(model.accounts) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if isNew {
                Picker("How often", selection: $often) {
                    Text("Once").tag(Often.once)
                    Text("Every month").tag(Often.monthly)
                }
                .pickerStyle(.segmented)
            }
            if often == .once {
                DatePicker("Came in on", selection: $receivedOn, in: ...Date.now, displayedComponents: .date)
            } else {
                Picker("Day of the month", selection: $day) {
                    ForEach(1...31, id: \.self) { Text(BillEditor.ordinal($0)).tag($0) }
                }
                Picker("For how long", selection: $length) {
                    Text("Until I stop it").tag(Length.open)
                    Text("3 months").tag(Length.months(3))
                    Text("6 months").tag(Length.months(6))
                    Text("1 year").tag(Length.months(12))
                    Text("2 years").tag(Length.months(24))
                    Text("Until a month…").tag(Length.until)
                }
                if length == .until {
                    DatePicker("Last month", selection: $untilMonth, in: Date.now..., displayedComponents: .date)
                }
                if isNew, day <= (Int(today.suffix(2)) ?? 1) {
                    Toggle("This month's has already come in: count it", isOn: $countThisMonth)
                }
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            if let problem = model.moneyProblem { Text(problem).font(.caption).foregroundStyle(.orange) }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear(perform: load)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save", action: save)
                    // What the server takes: a name of up to 300 characters and an amount under ten million.
                    .disabled(saving || note.trimmingCharacters(in: .whitespaces).isEmpty || note.count > 300
                              || (MoneyMath.parseAmount(amount) ?? 0) <= 0 || (isNew && often == .monthly && (lastMonth.map { $0 < firstMonth } ?? false)))
            }
        }
    }

    /// "From December, on the 25th, until April 2027 (5 times)."
    private var summary: String {
        let first = Self.monthWords(firstMonth)
        guard let last = lastMonth else { return "From \(first), on the \(BillEditor.ordinal(day)), until you stop it. Blink adds it on that day each month." }
        guard last >= firstMonth else { return "The last month is before the first one (\(first))." }
        var count = 1, m = firstMonth
        while m < last { m = MoneyMath.next(month: m); count += 1 }
        return "From \(first) to \(Self.monthWords(last)), on the \(BillEditor.ordinal(day)): \(count) time\(count == 1 ? "" : "s"). Blink adds it on that day each month."
    }

    private func load() {
        accountID = model.accounts.first(where: \.isDefault)?.id
        switch editing {
        case .new: break
        case .entry(let e):
            (note, accountID, often) = (e.note, e.accountID, .once)
            amount = e.amount.formatted(.number.grouping(.never).precision(.fractionLength(2)))
            receivedOn = HabitDay.date(fromKey: e.receivedOn) ?? .now
        case .plan(let p):
            (note, accountID, often, day) = (p.note, p.accountID, .monthly, p.day)
            amount = p.amount.formatted(.number.grouping(.never).precision(.fractionLength(2)))
            if let end = p.endsMonth {
                length = .until
                untilMonth = HabitDay.date(fromKey: end + "-01") ?? .now
            }
        }
    }

    private func save() {
        let value = MoneyMath.parseAmount(amount) ?? 0
        let name = note.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        Task {
            defer { saving = false }
            let saved: Bool
            switch (editing, often) {
            case (.plan(var plan), _):
                (plan.note, plan.amount, plan.accountID, plan.day, plan.endsMonth) = (name, value, accountID, day, lastMonth)
                saved = await model.saveIncomePlan(plan)
            case (.entry(let e), _):
                saved = await model.saveIncome(Income(id: e.id, amount: value, note: name, accountID: accountID,
                                                      receivedOn: HabitDay.key(receivedOn), planID: e.planID))
            case (.new, .once):
                saved = await model.saveIncome(Income(amount: value, note: name, accountID: accountID, receivedOn: HabitDay.key(receivedOn)))
            case (.new, .monthly):
                saved = await model.saveIncomePlan(IncomePlan(note: name, amount: value, accountID: accountID, day: day, endsMonth: lastMonth),
                                                   includeThisMonth: countThisMonth)
            }
            if saved { dismiss() } // a failure keeps the sheet, with the reason
        }
    }

    /// "2027-04" → "April 2027".
    static func monthWords(_ month: String) -> String {
        HabitDay.date(fromKey: month + "-01")?.formatted(.dateTime.month(.wide).year()) ?? month
    }
}
#endif
