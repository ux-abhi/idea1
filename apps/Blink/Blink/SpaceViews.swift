// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

extension Color {
    /// A Space's colour, stored on the server by its Apple system colour name.
    static func system(_ name: String) -> Color {
        switch name {
        case "purple": .purple
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "indigo": .indigo
        default: .blue
        }
    }
}

/// Done out of all tasks, as a ring with the percentage inside.
struct ProgressRing: View {
    let done: Int
    let total: Int
    let tint: Color

    var body: some View {
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 6)
            Circle().trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(total == 0 ? "–" : "\(Int((fraction * 100).rounded()))%")
                .font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
        }
        .frame(width: 60, height: 60)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(total == 0 ? "No tasks yet" : "\(done) of \(total) tasks done")
    }
}

/// "All · ● Website · ● Visa": which Space a page shows. Hidden when there are no Spaces.
struct SpaceFilter: View {
    @Environment(AppModel.self) private var model
    @Binding var selected: String

    var body: some View {
        if !model.spaces.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All", id: "all", color: nil)
                    ForEach(model.spaces) { space in chip(space.title, id: space.id, color: Color.system(space.color)) }
                }
            }
        }
    }

    private func chip(_ title: String, id: String, color: Color?) -> some View {
        let on = selected == id
        return Button { selected = id } label: {
            HStack(spacing: 5) {
                if let color { Circle().fill(color).frame(width: 7, height: 7) }
                Text(title).lineLimit(1)
            }
            .font(.callout.weight(on ? .semibold : .regular))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(on ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05), in: .capsule)
            .overlay(Capsule().strokeBorder(on ? Color.accentColor.opacity(0.5) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The small "● Website" tag on a task that belongs to a Space.
struct SpaceChip: View {
    let space: Space

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.system(space.color)).frame(width: 6, height: 6)
            Text(space.title).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("In \(space.title)")
    }
}

/// Right-click › Move to Space, for any task or note.
struct MoveToSpaceMenu: View {
    @Environment(AppModel.self) private var model
    let item: BlinkItem

    var body: some View {
        if !model.spaces.isEmpty {
            Menu("Move to Space") {
                ForEach(model.spaces) { space in
                    Button(space.title) { Task { await model.move(item, to: space.id) } }
                        .disabled(item.spaceID == space.id)
                }
                if item.spaceID != nil {
                    Divider()
                    Button("Remove from Space") { Task { await model.move(item, to: nil) } }
                }
            }
        }
    }
}

/// New Space: a name, an optional goal and due date, a colour.
struct NewSpaceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let created: (String) -> Void
    @State private var title = ""
    @State private var goal = ""
    @State private var color = "blue"
    @State private var hasDue = false
    @State private var due = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now

    var body: some View {
        Form {
            TextField("Name", text: $title, prompt: Text("e.g. Website launch"))
            TextField("Goal", text: $goal, prompt: Text("e.g. Launch by November"), axis: .vertical)
            Toggle("Due date", isOn: $hasDue)
            if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
            LabeledContent("Colour") {
                HStack(spacing: 6) {
                    ForEach(Space.colors, id: \.self) { name in
                        Button { color = name } label: {
                            Circle().fill(Color.system(name)).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: color == name ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name.capitalized)
                        .accessibilityAddTraits(color == name ? .isSelected : [])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let space = Space(title: title.trimmingCharacters(in: .whitespaces),
                                      goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                                      dueAt: hasDue ? due : nil, color: color)
                    Task { await model.createSpace(space) }
                    created(space.id)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
#endif
