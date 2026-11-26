// © Pexilim
import Foundation

/// The end-of-day recap (ADR-0005 §5): what got done today, so the day counts. Counted on the Mac from what Blink
/// already has; nothing is sent anywhere.
public struct DayRecap: Equatable, Sendable {
    public var tasks = 0, cards = 0, meetings = 0, mails = 0, mailsHandled = 0, habitsDone = 0, habitsDue = 0
    public var spent: Decimal = 0

    public init() {}

    /// `day` is the start of the owner's habit day. `tables` pairs each Space table with its loaded rows; `habits` is
    /// today's scheduled habits and how many were done.
    public static func make(day: Date, now: Date, tasks: [BlinkItem], tables: [(SpaceBlock, [SpaceRow])],
                            events: [AgendaEvent], emails: [EmailMessage], spends: [Spend], habits: (done: Int, due: Int),
                            calendar: Calendar = .current) -> DayRecap {
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let today = { (date: Date) in date >= day && date < end }
        var recap = DayRecap()
        // shortcut: a task counts on the day it was last changed, so editing an old done task counts it again; fine
        // until items store when they were done.
        recap.tasks = tasks.filter { $0.type == .task && $0.status == .done && today($0.updatedAt) }.count
        // shortcut: only done cards dated today count (rows don't store when they were ticked), until they do.
        recap.cards = tables.reduce(0) { sum, pair in
            let columns = pair.0.data.columns ?? []
            guard let date = columns.first(where: { $0.kind == .date }) else { return sum }
            return sum + pair.1.filter { row in
                SpaceTable.isDone(row, columns: columns)
                    && SpaceTable.when(row.cells[date.id] ?? "", calendar: calendar).map { today($0.date) } == true
            }.count
        }
        recap.meetings = events.filter { !$0.allDay && today($0.start) && $0.start <= now }.count
        let mails = emails.filter { today($0.receivedAt ?? $0.createdAt) }
        recap.mails = mails.count
        recap.mailsHandled = mails.filter { $0.status == .done || $0.status == .drafted }.count
        let key = HabitDay.key(day, calendar: calendar)
        recap.spent = spends.filter { $0.spentOn == key }.reduce(0) { $0 + $1.amount }
        (recap.habitsDone, recap.habitsDue) = habits
        return recap
    }

    /// "3 tasks and 2 cards done · 2 meetings · 9 of 12 mails handled · 2 of 3 habits · €42.50 spent".
    public var line: String {
        func count(_ n: Int, _ one: String) -> String { "\(n) \(one)\(n == 1 ? "" : "s")" }
        var parts: [String] = []
        switch (tasks, cards) {
        case (0, 0): break
        case (_, 0): parts.append(count(tasks, "task") + " done")
        case (0, _): parts.append(count(cards, "card") + " done")
        default: parts.append("\(count(tasks, "task")) and \(count(cards, "card")) done")
        }
        if meetings > 0 { parts.append(count(meetings, "meeting")) }
        if mails > 0 { parts.append("\(mailsHandled) of \(count(mails, "mail")) handled") }
        if habitsDue > 0 { parts.append("\(habitsDone) of \(count(habitsDue, "habit"))") }
        if spent > 0 { parts.append(spent.formatted(.currency(code: MoneyMath.currency)) + " spent") }
        return parts.isEmpty ? "A quiet day." : parts.joined(separator: " · ")
    }
}
