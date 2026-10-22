// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

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
