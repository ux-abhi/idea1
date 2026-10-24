// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Every shortcut, from the one shared list (BlinkKit `Shortcuts`, the same as design/shortcuts.json):
/// the Help › Keyboard Shortcuts window (⌘/) and the list in Settings.
struct ShortcutsView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 28, alignment: .top)], alignment: .leading, spacing: 24) {
                ForEach(Shortcuts.all) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name).font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(group.items) { ShortcutRow(item: $0) }
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 480, idealHeight: 620)
    }
}

/// The keys of one shortcut as a small key cap, as Settings shows them.
struct KeysLabel: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.callout.monospaced().weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 6, style: .continuous))
            .foregroundStyle(.primary)
    }
}

/// "⌃⌥Space   Ask Blink in the notch": the keys as a small key cap, then what they do.
struct ShortcutRow: View {
    let item: Shortcuts.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            KeysLabel(keys: item.keys).frame(minWidth: 110, alignment: .leading)
            Text(item.what).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Help › Keyboard Shortcuts (⌘/) and Show Tour.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("tour.v1.done") private var tourDone = false

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }
                .keyboardShortcut("/", modifiers: .command)
            Button("Show Tour") {
                tourDone = false
                openWindow(id: "tour")
            }
        }
    }
}
#endif
