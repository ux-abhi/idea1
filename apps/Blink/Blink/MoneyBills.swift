// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Fixed every month: rent, phone, subscriptions. Each shows its day and amount; on that day Blink adds the spend itself.
struct BillsCard: View {
    @Environment(AppModel.self) private var model
    @Binding var editing: FixedBill?

    var body: some View {
        let active = model.fixedBills.filter { !$0.paused }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fixed every month").font(.headline)
                Spacer()
                if !active.isEmpty {
                    Text(active.reduce(Decimal.zero) { $0 + $1.amount }, format: .currency(code: MoneyMath.currency).precision(.fractionLength(0)))
                        .font(.headline).monospacedDigit()
                }
            }
            if model.fixedBills.isEmpty {
                Text("Rent, phone, subscriptions: add them once and Blink adds each on its day.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.fixedBills) { bill in
                Button { editing = bill } label: { row(bill) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit…", systemImage: "pencil") { editing = bill }
                        Button(bill.paused ? "Resume" : "Pause", systemImage: bill.paused ? "play" : "pause") {
                            var changed = bill
                            changed.paused.toggle()
                            Task { await model.saveBill(changed) }
                        }
                        Button("Delete Bill", systemImage: "trash", role: .destructive) { Task { await model.deleteBill(bill) } }
                    }
            }
            Button("Add Fixed Expense", systemImage: "plus") {
                editing = FixedBill(accountID: model.accounts.first(where: \.isDefault)?.id,
                                    day: Calendar.current.component(.day, from: .now))
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .cardSurface(radius: Tokens.Radius.tile)
    }

    private func row(_ bill: FixedBill) -> some View {
        HStack(spacing: 10) {
            Image(systemName: bill.category.symbol).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(bill.note).font(.callout.weight(.medium)).lineLimit(1)
                Text(bill.paused ? "Paused" : "Every month on the \(BillEditor.ordinal(bill.day))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(bill.amount, format: .currency(code: MoneyMath.currency)).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .opacity(bill.paused ? 0.5 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit the bill")
    }
}

/// Adds or changes one fixed bill: what, how much, which day, category and account.
struct BillEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var bill: FixedBill
    @State private var amount = ""

    var body: some View {
        let isNew = !model.fixedBills.contains { $0.id == bill.id }
        Form {
            TextField("What", text: $bill.note, prompt: Text("Rent, phone, Netflix…"))
            TextField("Amount", text: $amount, prompt: Text("e.g. 850"))
            Picker("Day of the month", selection: $bill.day) {
                ForEach(1...31, id: \.self) { Text(Self.ordinal($0)).tag($0) }
            }
            Picker("Category", selection: $bill.category) {
                ForEach(SpendCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            if !model.accounts.isEmpty {
                Picker("Paid from", selection: $bill.accountID) {
                    Text("No account").tag(String?.none)
                    ForEach(model.accounts) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if let problem = model.moneyProblem { Text(problem).font(.caption).foregroundStyle(.orange) }
            Text("Blink adds it on that day each month\(bill.day > 28 ? " (the last day in shorter months)" : ""). If that day has passed this month, it starts next month.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onAppear { amount = bill.amount > 0 ? bill.amount.formatted(.number.grouping(.never).precision(.fractionLength(2))) : "" }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") {
                    bill.amount = MoneyMath.parseAmount(amount) ?? 0
                    bill.note = bill.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    let saving = bill
                    Task { if await model.saveBill(saving) { dismiss() } } // a failure keeps the sheet, with the reason
                }
                // What the server takes: a name of up to 300 characters and an amount under a million.
                .disabled(bill.note.trimmingCharacters(in: .whitespaces).isEmpty || bill.note.count > 300 || MoneyMath.parseAmount(amount) == nil)
            }
        }
    }

    /// "1st", "22nd", "31st".
    static func ordinal(_ day: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: day as NSNumber) ?? "\(day)"
    }
}
#endif
