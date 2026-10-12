// © Pexilim
import BlinkKit
import SwiftUI

/// Pick the model for one feature: Claude or a free Groq model. The same choice shows in Settings › AI & Usage.
struct ModelMenu: View {
    @Environment(AppModel.self) private var model
    let feature: String
    /// Compact: just the model's short name, for a panel header or next to a button.
    var compact = false

    var body: some View {
        let current = model.model(for: feature)
        Menu {
            Section("Claude") {
                ForEach(AIModel.all.filter { !$0.isFree }) { option($0, current: current) }
            }
            Section("Free (Groq)") {
                ForEach(AIModel.all.filter(\.isFree)) { option($0, current: current) }
            }
        } label: {
            if compact {
                Label(current.shortName, systemImage: current.isFree ? "leaf" : "sparkles")
            } else {
                Text(current.name)
            }
        }
        .fixedSize()
        .help("Model for \(feature == "chat" ? "chat and planning" : "content drafts")")
        .accessibilityLabel("Model: \(current.name)")
    }

    private func option(_ option: AIModel, current: AIModel) -> some View {
        Button {
            Task { await model.setModel(option.id, for: feature) }
        } label: {
            if option.id == current.id { Label(option.name, systemImage: "checkmark") } else { Text(option.name) }
        }
    }
}
