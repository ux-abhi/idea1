// © Pexilim
import BlinkKit
import SwiftUI

/// A just-in-time prompt where a feature needs a missing piece: "Add an AI key", "Add your Instagram handle".
struct NeedsSetup: View {
    let step: SetupStep
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: step.symbol).foregroundStyle(.orange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(step.title).font(.callout.weight(.semibold))
                Text(step.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Settings is a Mac window; on iPhone the steps live on the server and in Settings later (Phase 6).
            #if os(macOS)
            Button(step.action) { model.go(to: step.destination) }.buttonStyle(.borderedProminent).controlSize(.small)
            #endif
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
