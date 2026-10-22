// © Pexilim
#if os(macOS)
import AppKit
import BlinkKit
import Charts
import SwiftUI

/// Content › Overview: the connected accounts, then how the owner's posts perform (from the page reader, Apify).
struct ContentOverview: View {
    @Environment(AppModel.self) private var model
    let editVoice: () -> Void

    var body: some View {
        AccountsStrip()
        let posts = model.pagePosts
        if posts.isEmpty && !model.voice.page.contains("@") {
            EmptyCard(symbol: "person.crop.circle.badge.plus", title: "Add your Instagram handle first",
                      message: "Add your Instagram handle in Voice so Blink can read your posts.",
                      actionTitle: "Open Voice", action: editVoice)
        } else if posts.isEmpty {
            EmptyCard(symbol: "chart.bar.xaxis", title: "See how your posts perform",
                      message: "Read your latest posts to see what works (costs about 5 cents).",
                      actionTitle: model.readingPage ? nil : "Read My Page", action: { Task { await model.readPage() } })
        } else {
            metrics(ContentStats.summary(posts))
            // Reading again is here, where its numbers show (it costs a little, so not in the toolbar).
            DashCard("Engagement per post", trailing: model.readingPage ? "Reading…" : "Read Again",
                     action: { if !model.readingPage { Task { await model.readPage() } } }) {
                EngagementChart(posts: Array(ContentStats.newestFirst(posts).filter { $0.postedAt != nil }.prefix(30)))
                Text("Likes plus comments for each of your latest posts, coloured by format.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                DashCard("Best format") { FormatChart(rows: ContentStats.byFormat(posts)) }
                DashCard("Best day to post") { WeekdayChart(rows: ContentStats.byWeekday(posts)) }
            }
            DashCard("Posts per week") {
                WeeklyPostsChart(counts: ContentStats.perWeek(posts))
                Text("The last 8 weeks. Steady weeks beat bursts.").font(.caption).foregroundStyle(.secondary)
            }
            DashCard("Top posts") {
                CardRows(items: ContentStats.top(posts)) { TopPostRow(post: $0) }
            }
        }
        if let read = model.pageRead {
            DashCard("What works on @\(read.handle)", trailing: "Close", action: { model.dismissPageRead() }) {
                Text("From your last \(read.read) posts. Ideas and your week plan now build on your best ones.")
                    .font(.callout).foregroundStyle(.secondary)
                if let analysis = read.analysis {
                ForEach(analysis.works, id: \.self) { Label($0, systemImage: "hand.thumbsup").font(.callout) }
                ForEach(analysis.avoid, id: \.self) { Label($0, systemImage: "hand.thumbsdown").font(.callout).foregroundStyle(.secondary) }
                if !analysis.voice.page.isEmpty {
                    Divider()
                    Text("Suggested voice").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("\(analysis.voice.page)\nFor: \(analysis.voice.audience)\nTopics: \(analysis.voice.topics)\nTone: \(analysis.voice.tone)").font(.callout)
                    HStack {
                        Button("Use as My Voice") { Task { await model.useReadAsVoice() } }.buttonStyle(.borderedProminent)
                        Button("Edit Voice…", action: editVoice)
                    }
                }
                }
            }
        }
    }

    private func metrics(_ s: ContentStats.Summary) -> some View {
        let change = s.change.map { c -> (String, Color) in
            let pct = Int((abs(c) * 100).rounded())
            return (c >= 0 ? "▲ \(pct)% vs the \(s.posts) before" : "▼ \(pct)% vs the \(s.posts) before", c >= 0 ? .green : .orange)
        }
        return HStack(spacing: 12) {
            MetricTile(title: "Likes per post", text: s.averageLikes.formatted(), detail: "Latest \(s.posts) posts")
            MetricTile(title: "Comments per post", text: s.averageComments.formatted(), detail: "Latest \(s.posts) posts")
            MetricTile(title: "Views per reel", text: s.averageReelViews?.formatted() ?? "—", detail: s.averageReelViews == nil ? "No reels lately" : "Reels only")
            MetricTile(title: "Engagement trend", text: change.map { _ in s.change! >= 0 ? "Up" : "Down" } ?? "—",
                       detail: change?.0 ?? "Needs more posts", detailColor: change?.1 ?? .secondary)
        }
    }
}

/// Instagram, LinkedIn and X with their follower numbers (typed in; Instagram's posts come through Apify).
private struct AccountsStrip: View {
    @Environment(AppModel.self) private var model
    @State private var editing: SocialAccount.Platform?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(SocialAccount.Platform.allCases) { platform in
                let account = model.socialAccounts.first { $0.platform == platform }
                Button { editing = platform } label: { tile(platform, account) }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(get: { editing == platform }, set: { if !$0 { editing = nil } }), arrowEdge: .bottom) {
                        FollowersEditor(platform: platform, account: account) { editing = nil }
                    }
            }
        }
    }

    private func tile(_ platform: SocialAccount.Platform, _ account: SocialAccount?) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(platform.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            if let followers = account?.followers {
                Text(followers.formatted(.number.notation(.compactName))).font(.system(.title2, design: .rounded).weight(.semibold))
                Text("followers\(account?.handle.isEmpty == false ? " · \(account!.handle)" : "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(account == nil ? "Add" : "No account").font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(.secondary)
                Text(account == nil ? "Your follower count" : "Not on \(platform.name) yet").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Tokens.Radius.tile)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit the follower number")
    }
}

/// Types in a follower count for one platform, or marks "no account yet".
private struct FollowersEditor: View {
    @Environment(AppModel.self) private var model
    let platform: SocialAccount.Platform
    let account: SocialAccount?
    let done: () -> Void
    @State private var handle = ""
    @State private var followers = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(platform.name) followers").font(.headline)
            TextField(platform == .linkedin ? "Name or profile" : "@handle", text: $handle).textFieldStyle(.roundedBorder)
            TextField("Followers, e.g. 1400", text: $followers).textFieldStyle(.roundedBorder)
            Text("Update it now and then; Blink shows the latest number you typed.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("No Account Yet") { save(nil) }
                Spacer()
                // Whole numbers only: "1.4k" would otherwise be read as 14.
                Button("Save") { save(Int(followers.filter(\.isNumber))) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(Int(followers.filter(\.isNumber)) == nil || followers.contains(where: \.isLetter))
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            handle = account?.handle ?? ""
            followers = account?.followers.map(String.init) ?? ""
        }
    }

    private func save(_ count: Int?) {
        Task { await model.setFollowers(count, handle: handle.trimmingCharacters(in: .whitespaces), on: platform) }
        done()
    }
}

private struct TopPostRow: View {
    let post: PagePost

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: post.kind.symbol).foregroundStyle(.secondary).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.caption.isEmpty ? post.kind.title : post.caption).lineLimit(1)
                Text([post.postedAt.map { $0.formatted(date: .abbreviated, time: .omitted) }, post.kind.title].compactMap(\.self).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text([post.likes.map { "\($0.formatted()) likes" }, post.comments.map { "\($0) comments" }, post.views.map { "\($0.formatted(.number.notation(.compactName))) views" }]
                .compactMap(\.self).joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let link = URL(string: post.url) {
                Link(destination: link) { Image(systemName: "arrow.up.right.square") }.help("Open on Instagram")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open on Instagram") { if let link = URL(string: post.url) { NSWorkspace.shared.open(link) } }
    }
}

// MARK: Charts

private struct EngagementChart: View {
    let posts: [PagePost]

    var body: some View {
        Chart(posts.reversed()) { post in
            BarMark(x: .value("Posted", post.postedAt ?? .distantPast, unit: .day), y: .value("Engagement", post.engagement))
                .foregroundStyle(by: .value("Format", post.kind.title))
                .cornerRadius(3)
        }
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 200)
        .accessibilityLabel("Engagement per post")
    }
}

private struct FormatChart: View {
    let rows: [(kind: PagePost.Kind, posts: Int, engagement: Int, views: Int?)]

    var body: some View {
        Chart(rows, id: \.kind) { row in
            BarMark(x: .value("Engagement", row.engagement), y: .value("Format", row.kind.title))
                .foregroundStyle(by: .value("Format", row.kind.title))
                .annotation(position: .trailing) {
                    Text("\(row.posts) post\(row.posts == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
                }
                .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .frame(height: 140)
        .accessibilityLabel("Average engagement by format")
        .accessibilityValue(rows.map { "\($0.kind.title) \($0.engagement)" }.formatted())
    }
}

private struct WeekdayChart: View {
    let rows: [(weekday: Int, posts: Int, engagement: Int)]

    var body: some View {
        let best = rows.max { $0.engagement < $1.engagement }?.weekday
        Chart(rows, id: \.weekday) { row in
            BarMark(x: .value("Day", Calendar.current.shortWeekdaySymbols[row.weekday - 1]), y: .value("Engagement", row.engagement))
                .foregroundStyle(row.weekday == best ? Color.accentColor : Color.accentColor.opacity(0.4))
                .cornerRadius(3)
        }
        .frame(height: 140)
        .accessibilityLabel("Average engagement by weekday")
        .accessibilityValue(best.map { "Best on \(Calendar.current.weekdaySymbols[$0 - 1])" } ?? "")
    }
}

private struct WeeklyPostsChart: View {
    let counts: [Int]

    var body: some View {
        Chart(Array(counts.enumerated()), id: \.offset) { week, count in
            BarMark(x: .value("Week", week == counts.count - 1 ? "This week" : "\(counts.count - 1 - week)w ago"), y: .value("Posts", count))
                .foregroundStyle(week == counts.count - 1 ? Color.accentColor : Color.accentColor.opacity(0.45))
                .cornerRadius(3)
        }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .frame(height: 120)
        .accessibilityLabel("Posts per week, last 8 weeks")
        .accessibilityValue(counts.map(String.init).joined(separator: ", "))
    }
}
#endif
