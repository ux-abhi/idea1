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
        // Only what can run: models whose service is connected, and the on-device one for chat.
        let available = AIModel.available(for: feature, keys: model.keyStatus)
            .filter { $0.id != AIModel.onDeviceID || OnDeviceChat.problem == nil }
        Menu {
            ForEach(AIModel.Group.allCases.filter { group in available.contains { $0.group == group } }, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(available.filter { $0.group == group }) { option($0, current: current) }
                }
            }
            if available.isEmpty { Text("No AI connected yet") }
            Divider()
            Button(available.isEmpty ? "Connect an AI…" : "Connect Another AI…") { model.openSettings("connections") }
        } label: {
            if !model.hasModel(for: feature) {
                Label("Connect AI", systemImage: "key")
            } else if compact {
                Label(current.shortName, systemImage: current.group == .onDevice ? "laptopcomputer" : current.isFree ? "leaf" : current.group == .best ? "star" : "sparkles")
            } else {
                Text(current.name)
            }
        }
        .fixedSize()
        .help("Model for \(["chat": "chat and planning", "content": "content drafts", "voice": "voice commands and tidying dictation", "text": "quick text edits"][feature] ?? feature)")
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
