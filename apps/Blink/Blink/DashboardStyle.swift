// © Pexilim
#if os(macOS)
import BlinkKit
import SwiftUI

/// Shared look for every window page (DESIGN.md Look v3): soft canvas, big rounded title, rounded cards.

/// The soft blue-grey canvas: the window background with a faint wash of the accent colour.
struct BlinkCanvas: View {
    var body: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.06), Color(nsColor: .windowBackgroundColor)],
                       startPoint: .topLeading, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// A scrolling page: title and summary on top, cards below, on the canvas.
struct DashPage<Content: View>: View {
    let title: String
    let summary: String
    @ViewBuilder let content: Content

    init(_ title: String, summary: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    Text(summary).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
                content
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(BlinkCanvas())
    }
}

/// A rounded card with a title, and an optional link on the right.
struct DashCard<Content: View>: View {
    let title: String?
    var trailing: String?
    var action: (() -> Void)?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, trailing: String? = nil, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    if let trailing, let action {
                        Button(trailing, action: action).buttonStyle(.plain).foregroundStyle(.secondary)
                    } else if let trailing {
                        Text(trailing).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: Tokens.Radius.notchOpen - 6, style: .continuous))
    }
}

/// A card that folds; whether it's open is remembered per key (Inbox and Content sections).
struct FoldingCard<Content: View>: View {
    let title: String
    let count: Int
    @AppStorage private var open: Bool
    @ViewBuilder let content: Content

    init(key: String, title: String, count: Int, openByDefault: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        _open = AppStorage(wrappedValue: openByDefault, "open.\(key)")
        self.content = content()
    }

    var body: some View {
        DashCard {
            DisclosureGroup(isExpanded: $open) {
                content.padding(.top, 8)
            } label: {
                Text("\(title) · \(count)").font(.headline)
            }
        }
    }
}

/// A search field inside the page rather than in the window toolbar: toolbar search fields on several pages make
/// AppKit's toolbar insert the same item twice when pages switch, which crashes the app.
struct PageSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: .capsule)
        .frame(maxWidth: 280)
    }
}

/// An empty card that says what will appear and how (§36.2), with an optional action.
struct EmptyCard: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        DashCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(message).foregroundStyle(.secondary)
                    if let actionTitle, let action {
                        Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4)
                    }
                }
            }
        }
    }
}

/// "Done: Call Sam · Undo" at the bottom of the window for a few seconds after something is ticked off (⌘Z works too).
struct UndoToast: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let chip = model.undoChip {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                Text(chip.text).lineLimit(1)
                Button("Undo") { Task { await model.undo() } }
                    .keyboardShortcut("z", modifiers: .command)
            }
            .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 8)
            .background(.regularMaterial, in: .capsule)
            .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            .padding(.bottom, 20)
            .id(chip.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear { AccessibilityNotification.Announcement("\(chip.text). Undo available.").post() }
        }
    }
}

/// Rows separated by thin dividers, for inside a card.
struct CardRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                row(item).frame(maxWidth: .infinity, alignment: .leading) // rows start at the card's edge
            }
        }
    }
}
#endif
