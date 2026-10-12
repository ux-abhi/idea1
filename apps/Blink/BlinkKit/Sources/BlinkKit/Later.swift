// © Pexilim
import Foundation

/// "Later" for a task or reminder (§36.2 word list: Later, not Snooze): a few sensible next times from now.
public enum Later {
    public static func choices(now: Date, calendar: Calendar = .current) -> [(title: String, date: Date)] {
        var list: [(String, Date)] = []
        if let hour = calendar.date(byAdding: .hour, value: 1, to: now) { list.append(("In 1 hour", hour)) }
        if let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now), evening > now.addingTimeInterval(3600) {
            list.append(("This evening, 18:00", evening))
        }
        let today = calendar.startOfDay(for: now)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
            list.append(("Tomorrow, 9:00", nine))
        }
        // The Monday after tomorrow, so on a Monday it means a week away, not this morning.
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           let monday = calendar.nextDate(after: tomorrow, matching: DateComponents(hour: 9, minute: 0, weekday: 2), matchingPolicy: .nextTime),
           monday > (list.last?.1 ?? now) {
            list.append(("Next Monday, 9:00", monday))
        }
        return list
    }
}
