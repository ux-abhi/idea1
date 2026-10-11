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
