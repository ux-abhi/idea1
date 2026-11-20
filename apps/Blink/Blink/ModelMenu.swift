// © Pexilim
import BlinkKit
import SwiftUI

/// The model for one feature: Automatic (Blink picks from what's connected, by Settings › AI › Quality) or one picked by
/// hand from the connected services. The same choice shows in Settings › AI.
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
        let automatic = !model.pickedModels.contains(feature) && !(feature == "chat" && current.id == AIModel.onDeviceID)
        Menu {
            if !available.isEmpty {
                Button {
                    Task { await model.setModelAutomatic(feature) }
                } label: {
                    let text = "Automatic: \(model.modelQuality == .best ? "best" : "free") model you've connected"
                    if automatic { Label(text, systemImage: "checkmark") } else { Text(text) }
                }
                Divider()
            }
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
            } else if automatic && !compact {
                Text("Auto · \(current.shortName)")
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
            // A checkmark only on a model picked by hand; Automatic carries its own.
            if option.id == current.id && (model.pickedModels.contains(feature) || option.id == AIModel.onDeviceID) { Label(option.name, systemImage: "checkmark") } else { Text(option.name) }
        }
    }
}
