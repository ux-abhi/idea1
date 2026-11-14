// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// The step-by-step guide on the website (marketing/site/app/apple-pay), which keeps the same steps as `CaptureSetup`.
enum CaptureGuide {
    static let url = URL(string: "https://www.blinkk.app/apple-pay")!
}

/// Apple Pay taps arrive on their own: through a Shortcuts automation on the owner's iPhone (no Blink iPhone app needed).
struct ApplePayCard: View {
    @Environment(AppModel.self) private var model
    @State private var settingUp = false
    @State private var removing: CaptureToken?

    var body: some View {
        DashCard("Apple Pay", trailing: model.captureTokens.isEmpty ? nil : "Add Another iPhone", action: model.captureTokens.isEmpty ? nil : { settingUp = true }) {
            if model.captureTokens.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "wave.3.right.circle.fill").font(.title).foregroundStyle(.blue).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Catch every tap automatically").font(.headline)
                        Text("Pay with Apple Pay on your iPhone and the spend shows up here within seconds, sorted. Receipts in your mail are added too, never twice.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("About 3 minutes: Blink makes a private link, then you add one automation in the iPhone's Shortcuts app. No app to install.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 14) {
                            Button("Set Up on iPhone…") { settingUp = true }.buttonStyle(.borderedProminent)
                            Link("See the steps first", destination: CaptureGuide.url)
                        }
                        .padding(.top, 4)
                    }
                }
            } else {
                ForEach(model.captureTokens) { token in
                    HStack {
                        Image(systemName: "iphone").foregroundStyle(.secondary).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(token.name)
                            Text(token.lastUsedAt.map { "Last tap \($0.formatted(.relative(presentation: .named)))" } ?? "Waiting for the first tap")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) { removing = token }
                            .buttonStyle(.borderless)
                            .help("This iPhone stops sending taps. Make a new link to start again.")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .confirmationDialog("Remove \(removing?.name ?? "this iPhone")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { token in
            Button("Remove", role: .destructive) { Task { await model.removeCaptureLink(token) } }
        } message: { _ in
            Text("Its Apple Pay taps stop coming in. To start again you make a new link and redo the Shortcuts steps on the iPhone.")
        }
        .sheet(isPresented: $settingUp) { CaptureSetup() }
    }
}

/// Makes a capture link and walks the owner through the iPhone Shortcuts automation, step by step.
private struct CaptureSetup: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = "iPhone"
    @State private var token: String?
    @State private var making = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Catch Apple Pay on your iPhone").font(.title2.bold())
            if let token, let endpoint = model.captureEndpoint {
                Text("Copy each value here, then paste it on your iPhone (Universal Clipboard). Blink shows the key only now.")
                    .foregroundStyle(.secondary)
                CopyRow(label: "Address", value: endpoint.absoluteString)
                CopyRow(label: "Key", value: "Bearer \(token)", secret: true)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Step(1, "On your iPhone, open **Shortcuts** › **Automation** › **+** › **Transaction**. Pick your cards, choose **Run Immediately**, then **New Blank Automation**.")
                    Step(2, "Add **Get Contents of URL**. Paste the **Address**. Tap **›**: Method **POST**.")
                    Step(3, "Under **Headers** add `Authorization` and paste the **Key**.")
                    Step(4, "Under **Request Body** choose **JSON** and add three text fields: `amount` → **Shortcut Input › Amount**, `merchant` → **Merchant**, `card` → **Card or Pass**.")
                    Step(5, "Optional: add **Show Notification** with **Contents of URL** to see what Blink saved.")
                    Step(6, "Pay with Apple Pay. The spend appears in Money; change or delete it there.")
                }
                .fixedSize(horizontal: false, vertical: true)
                Link("The same steps with a picture of the finished action, and fixes if a tap doesn't show up", destination: CaptureGuide.url)
                    .font(.callout)
                Text("Blink names the account from the card (a card called “Visa Debit” goes to your Visa account), else your default account.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Blink makes a private link for this iPhone. Your iPhone sends each Apple Pay tap to your own server with it; nobody else sees your spending.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("Name", text: $name, prompt: Text("e.g. iPhone 15")).textFieldStyle(.roundedBorder)
                if let problem = model.moneyProblem, !making {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            HStack {
                Spacer()
                if token == nil {
                    Button("Cancel", role: .cancel) { dismiss() }
                    Button("Make Link") {
                        Task {
                            making = true
                            token = await model.makeCaptureLink(name: name.trimmingCharacters(in: .whitespaces))
                            making = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(making || name.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

struct CopyRow: View {
    let label: String
    let value: String
    var secret = false
    @State private var copied = false

    var body: some View {
        HStack {
            Text(label).font(.headline).frame(width: 70, alignment: .leading)
            Text(value).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer()
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                // A key: clipboard managers (Blink's own history included) skip concealed items.
                if secret { NSPasteboard.general.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) }
                copied = true
            }
            .accessibilityLabel(copied ? "\(label) copied" : "Copy \(label)")
        }
        .accessibilityElement(children: .contain)
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey
    init(_ number: Int, _ text: LocalizedStringKey) { (self.number, self.text) = (number, text) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.headline).foregroundStyle(.blue).frame(width: 18)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
