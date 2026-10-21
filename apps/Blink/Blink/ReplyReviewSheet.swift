// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// The reply exactly as it will go out: edit it, pick now or a time, and send with Touch ID (ARCHITECTURE §36.5).
struct ReplyReviewSheet: View {
    @Environment(AppModel.self) private var model
    @State var review: AppModel.Review
    @State private var later: Bool
    @State private var date: Date
    @State private var sending = false
    @State private var problem: String?

    init(review: AppModel.Review) {
        _review = State(initialValue: review)
        _later = State(initialValue: review.sendAt != nil)
        // Later defaults to tomorrow at 09:00.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        _date = State(initialValue: review.sendAt ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reply to \(review.sender)").font(.title3.weight(.semibold))
            Form {
                LabeledContent("From", value: review.draft.from)
                TextField("To", text: $review.draft.to)
                TextField("Subject", text: $review.draft.subject)
            }
            TextEditor(text: $review.draft.body)
                .font(.body)
                .frame(minHeight: 240)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: .rect(cornerRadius: 8))
                .accessibilityLabel("Message")
            HStack(spacing: 12) {
                Picker("Send", selection: $later) {
                    Text("Now").tag(false)
                    Text("Later").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                if later {
                    DatePicker("Send at", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
            Text(later ? "Touch ID confirms. It goes out at that time; you can cancel it until then in the Inbox."
                       : "Touch ID confirms. You get about 20 seconds to cancel before it goes.")
                .font(.callout).foregroundStyle(.secondary)
            if let problem, !problem.isEmpty {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            HStack {
                Text("A copy is in your Drafts in Apple Mail.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { model.reviewing = nil }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await send() }
                } label: {
                    if sending { ProgressView().controlSize(.small) } else { Text(later ? "Schedule" : "Send") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command) // never a bare Return: it sends mail
                .disabled(!canSend || sending)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var canSend: Bool {
        review.draft.hasValidRecipient && !review.draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!later || date > .now)
    }

    private func send() async {
        sending = true
        defer { sending = false }
        review.sendAt = later ? date : nil
        problem = await model.send(review)
    }
}
#endif
