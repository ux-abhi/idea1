// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// The owner's accounts with their balance now (what they last set, minus spends from it since), and the total.
struct AccountsCard: View {
    @Environment(AppModel.self) private var model
    @Binding var editing: AccountEditor.Mode?

    var body: some View {
        DashCard("Accounts", trailing: "Add Account", action: { editing = .new }) {
            if model.accounts.isEmpty {
                Text("Add your bank, savings, cash and card accounts with today's balance. Blink then shows how much you have, what's left at month end and how long it lasts. Spends come off the account you name (\"groceries 23.40 from Visa\") or your default one.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.accounts) { account in
                AccountRow(account: account, edit: { editing = .balance(account) })
            }
            if model.accounts.count > 1 {
                Divider()
                HStack {
                    Text("Total").font(.headline)
                    Spacer()
                    Text(MoneyMath.totalBalance(model.accounts), format: .currency(code: MoneyMath.currency))
                        .font(.headline).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct AccountRow: View {
    @Environment(AppModel.self) private var model
    let account: MoneyAccount
    let edit: () -> Void
    @State private var deleting = false

    var body: some View {
        let now = MoneyMath.balance(of: account)
        HStack(spacing: 10) {
            Image(systemName: account.kind.symbol).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name).font(.body.weight(.medium))
                    if account.isDefault {
                        Text("Default").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(.quaternary, in: .capsule)
                    }
                }
                Text("\(account.kind.title) · balance set \(account.balanceAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(now, format: .currency(code: MoneyMath.currency)).monospacedDigit().foregroundStyle(now < 0 ? .red : .primary)
            Menu("Account", systemImage: "ellipsis.circle") { menu }
                .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .contentShape(.rect)
        .onTapGesture(perform: edit)
        .contextMenu { menu }
        .confirmationDialog("Delete \(account.name)?", isPresented: $deleting) {
            Button("Delete Account", role: .destructive) { Task { await model.deleteAccount(account) } }
        } message: {
            Text("Its balance goes. Spending you added stays, without an account.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.name), \(now.formatted(.currency(code: MoneyMath.currency)))\(account.isDefault ? ", default" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Update the balance")
    }

    @ViewBuilder
    private var menu: some View {
        Button("Update Balance…", systemImage: "pencil", action: edit)
        if !account.isDefault {
            Button("Make Default", systemImage: "star") { Task { await model.makeDefault(account) } }
        }
        Button("Delete Account…", systemImage: "trash", role: .destructive) { deleting = true }
    }
}

/// Adds an account, or sets an account's balance to what the bank shows now.
struct AccountEditor: View {
    enum Mode: Identifiable {
        case new, balance(MoneyAccount)
        var id: String { if case .balance(let a) = self { a.id } else { "new" } }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var name = ""
    @State private var kind: MoneyAccount.Kind = .checking
    // Text, not a number field: a macOS number field only commits on Return.
    @State private var balance = ""

    private var account: MoneyAccount? { if case .balance(let a) = mode { a } else { nil } }
    private var parsed: Decimal? { MoneyMath.parseBalance(balance) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(account.map { "Balance of \($0.name)" } ?? "Add an Account").font(.headline)
            if account == nil {
                TextField("Name, e.g. Checking, Savings, Cash", text: $name).textFieldStyle(.roundedBorder)
                Picker("Type", selection: $kind) {
                    ForEach(MoneyAccount.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            }
            TextField("Balance now, e.g. 1250,40", text: $balance).textFieldStyle(.roundedBorder)
            Text(account == nil ? "What the bank shows today. Spends from this account come off it until you update it."
                                : "What the bank shows now. Spends entered from now on come off this.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(account == nil ? "Add" : "Save") {
                    guard let value = parsed else { return }
                    Task {
                        if let account { await model.setBalance(value, of: account) }
                        else { await model.addAccount(name: name.trimmingCharacters(in: .whitespaces), kind: kind, balance: value) }
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(parsed == nil || (account == nil && name.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(18)
        .frame(width: 380)
        .onAppear { if let account { balance = "\(MoneyMath.balance(of: account))" } }
    }
}
#endif
