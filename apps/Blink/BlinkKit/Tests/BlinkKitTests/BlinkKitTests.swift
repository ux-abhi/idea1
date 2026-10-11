// © Pexilim
import Foundation
import Supabase
import Testing
@testable import BlinkKit

@Suite struct ServerConfigTests {
    @Test func keepsOnlySchemeAndHost() throws {
        let config = try ServerConfig.validate(url: "  https://Example.supabase.co/rest/v1?x=1 ", key: " sb_publishable_abc ")
        #expect(config.url.absoluteString == "https://example.supabase.co")
        #expect(config.publishableKey == "sb_publishable_abc")
        #expect(config.host == "example.supabase.co")
    }

    @Test(arguments: [
        ("http://example.supabase.co", ServerConfig.Problem.notHTTPS),
        ("example.supabase.co", .invalidURL),
        ("", .invalidURL),
        ("https://user:pw@example.supabase.co", .invalidURL),
    ])
    func rejectsBadURLs(url: String, problem: ServerConfig.Problem) {
        #expect(throws: problem) { try ServerConfig.validate(url: url, key: "sb_publishable_abc") }
    }

    @Test func rejectsEmptyAndSecretKeys() {
        let url = "https://example.supabase.co"
        #expect(throws: ServerConfig.Problem.emptyKey) { try ServerConfig.validate(url: url, key: "  ") }
        #expect(throws: ServerConfig.Problem.secretKey) { try ServerConfig.validate(url: url, key: "sb_secret_abc") }
        #expect(throws: ServerConfig.Problem.secretKey) { try ServerConfig.validate(url: url, key: jwt(role: "service_role")) }
        #expect(throws: Never.self) { try ServerConfig.validate(url: url, key: jwt(role: "anon")) }
    }

    private func jwt(role: String) -> String {
        let payload = Data(#"{"iss":"supabase","role":"\#(role)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(payload).sig"
    }
}

@Suite struct MoodTests {
    private let tokens = Tokens.json

    @Test func everyTintMatchesItsToken() throws {
        let blink = try #require(tokens["blink"] as? [String: Any])
        for tint in MoodTint.allCases {
            guard let token = tint.token else { continue }
            let entry = try #require(blink[token] as? [String: Any], "missing \(token)")
            let expected = entry["maps"] as? String ?? (entry["value"] as? String == "#FFFFFF" ? "white" : nil)
            #expect(tint.appleName == expected, "\(token)")
        }
    }

    @Test func moodsMapToTheArchitectureTable() {
        #expect(Mood.headsUp.tint == .headsUp)
        #expect(Mood.important.tint == .important)
        #expect(Mood.thinking.tint == .thinking)
        #expect(Mood.done.tint == .done)
        #expect(Mood.concerned.tint == .attention)
        #expect(Mood.celebrate.tint == .celebrate)
        #expect(Mood.focus.tint == .dimmed && Mood.focus.pose == .closed)
        #expect(Mood.done.pose.bite == 1 && Mood.celebrate.pose.bite == 1)
        #expect(Mood.headsUp.pose == .wide && Mood.idle.pose == .pill)
    }

    /// Never colour alone: moods sharing a colour differ in shape, and every mood has its own word.
    @Test func noMoodReliesOnColourAlone() {
        #expect(Set(Mood.allCases.map(\.word)).count == Mood.allCases.count)
        for a in Mood.allCases {
            for b in Mood.allCases where a != b && a.tint == b.tint && a.pose == b.pose {
                // Morning is Idle reached by an opening animation; that pair is allowed by §7.
                #expect(Set([a, b]) == [.idle, .morning], "\(a) and \(b) look the same")
            }
        }
    }
}

@Suite struct TokensTests {
    @Test func motionMatchesTokensJSON() throws {
        let motion = try #require(Tokens.json["motion"] as? [String: Any])
        let springs = try #require(motion["spring"] as? [String: [String: Any]])
        let timing = try #require(motion["timing"] as? [String: [String: Any]])
        func spring(_ name: String) -> Tokens.Spring? {
            guard let s = springs[name], let r = s["response"] as? Double, let d = s["damping"] as? Double else { return nil }
            return .init(response: r, damping: d)
        }
        func dur(_ name: String) -> Double? { timing[name]?["dur"] as? Double }
        let m = Tokens.Motion.self

        #expect(spring("eyeShape") == m.eyeShape)
        #expect(spring("success") == m.success)
        #expect(spring("focus") == m.focus)
        #expect(spring("peek") == m.peek)
        #expect(spring("open") == m.open)
        #expect(spring("close") == m.close)
        #expect(spring("content") == m.content)
        #expect((motion["hover"] as? [String: Any])?["intentIn"] as? Double == m.hoverIntentIn)
        #expect((motion["hover"] as? [String: Any])?["graceOut"] as? Double == m.hoverGraceOut)
        #expect((motion["choreography"] as? [String: Any])?["contentDelay"] as? Double == m.contentDelay)
        #expect(dur("blinkClose") == m.blinkClose.dur)
        #expect(dur("blinkOpen") == m.blinkOpen.dur)
        #expect(dur("moodTint") == m.moodTint.dur)
        #expect(dur("contentOut") == m.contentOut.dur)
        #expect(dur("importantPulse") == m.importantPulse.dur)
        #expect(dur("morningOpen") == m.morningOpen.dur)
        #expect(dur("sleepyClose") == m.sleepyClose.dur)
        #expect(dur("celebrateBurst") == m.celebrateBurst.dur)
        #expect(dur("thinkingCycle") == m.thinkingCycle.dur)
        #expect(timing["thinkingCycle"]?["slowDur"] as? Double == m.thinkingSlowDur)
        #expect(timing["thinkingCycle"]?["slowAfter"] as? Double == m.thinkingSlowAfter)
        #expect(timing["thinkingCycle"]?["freezeAfter"] as? Double == m.thinkingFreezeAfter)
        #expect(timing["celebrateBurst"]?["maxParticles"] as? Int == m.celebrateMaxParticles)
        #expect(timing["blinkInterval"]?["min"] as? Double == m.blinkIntervalMin)
        #expect(timing["blinkInterval"]?["max"] as? Double == m.blinkIntervalMax)
        #expect(timing["blinkInterval"]?["doubleBlinkChance"] as? Double == m.doubleBlinkChance)
        #expect(springs["eyeShape"]?["rm"] as? String == "crossfade \(m.eyeShapeReduceMotion.dur)")

        let fps = try #require(motion["fps"] as? [String: Any])
        #expect((fps["ambient"] as? [String: Any])?["preferred"] as? Double == m.ambientFPS)
        let radius = try #require((Tokens.json["shape"] as? [String: Any])?["radius"] as? [String: Any])
        #expect(radius["notchRest"] as? Double == Tokens.Radius.notchRest)
        #expect(radius["notchOpen"] as? Double == Tokens.Radius.notchOpen)
        let glow = try #require(Tokens.json["glow"] as? [String: Any])
        #expect(glow["alpha"] as? Double == Tokens.Glow.alpha)
        #expect(glow["blurPt"] as? Double == Tokens.Glow.blur)
    }
}

@Suite struct AppLockTests {
    @Test func relocksAfterFiveMinutesAway() {
        let now = Date.now
        #expect(!AppLock.shouldRelock(awaySince: nil, now: now))
        #expect(!AppLock.shouldRelock(awaySince: now.addingTimeInterval(-299), now: now))
        #expect(AppLock.shouldRelock(awaySince: now.addingTimeInterval(-300), now: now))
        #expect(!AppLock.shouldRelock(awaySince: now.addingTimeInterval(-300), now: now, after: 900))
        #expect(AppLock.shouldRelock(awaySince: now.addingTimeInterval(-60), now: now, after: 60))
    }
}

@Suite struct ServerProblemTests {
    @Test func putsErrorsIntoWords() {
        #expect(ServerProblem(URLError(.notConnectedToInternet)) == .unreachable)
        #expect(ServerProblem(AuthError.sessionMissing) == .signedOut)
        let wrong = AuthError.api(message: "Invalid login credentials", errorCode: .invalidCredentials,
                                  underlyingData: Data(), underlyingResponse: HTTPURLResponse())
        #expect(ServerProblem(wrong) == .wrongLogin)
    }
}

extension Tokens {
    /// design/tokens.json, read from the repo.
    nonisolated(unsafe) static let json: [String: Any] = {
        let url = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../../design/tokens.json").standardized
        let data = (try? Data(contentsOf: url)) ?? Data("{}".utf8)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }()
}

@Suite struct AgendaTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()
    private func at(_ h: Int, _ m: Int, day: Int = 11) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }
    private func event(_ title: String, _ start: Date, minutes: Double = 30) -> AgendaEvent {
        AgendaEvent(extID: title, title: title, start: start, end: start.addingTimeInterval(minutes * 60))
    }

    @Test func statusLineCountsDownThenCountsUp() {
        let agenda = Agenda(events: [event("Review", at(15, 0))], reminders: [])
        #expect(agenda.statusLine(now: at(14, 48), calendar: cal) == "Review in 12 min")
        #expect(agenda.statusLine(now: at(14, 59, ).addingTimeInterval(30), calendar: cal) == "Review in 1 min")
        #expect(agenda.statusLine(now: at(15, 0), calendar: cal) == "Review now")
        #expect(agenda.statusLine(now: at(15, 3), calendar: cal) == "Review · started 3 min ago")
        #expect(agenda.statusLine(now: at(15, 30), calendar: cal) == "All clear") // ended
    }

    @Test func farEventsShowTheTimeAndTomorrowIsNotToday() {
        let agenda = Agenda(events: [event("Lunch", at(13, 0)), event("Tomorrow", at(9, 0, day: 12))], reminders: [])
        #expect(agenda.statusLine(now: at(9, 0), calendar: cal).hasPrefix("Next: Lunch at "))
        #expect(agenda.today(now: at(14, 0), calendar: cal).isEmpty)
        #expect(agenda.next(after: at(14, 0))?.title == "Tomorrow")
    }

    @Test func remindersShowWhenNoEventsAreLeft() {
        let one = Agenda(events: [], reminders: [AgendaReminder(id: "1", title: "Pay rent", due: nil)])
        #expect(one.statusLine(now: at(9, 0), calendar: cal) == "All clear") // undated: not due today
        #expect(Agenda.empty.statusLine(now: at(9, 0), calendar: cal) == "All clear")
    }

    @Test func meetingCuesFollowTheClock() {
        let review = event("Review", at(15, 0))
        let agenda = Agenda(events: [review], reminders: [])
        #expect(agenda.cue(now: at(14, 49)) == nil)
        #expect(agenda.cue(now: at(14, 50)) == .headsUp(review))
        #expect(agenda.cue(now: at(14, 56)) == .headsUp(review))
        #expect(agenda.cue(now: at(14, 57)) == .imminent(review)) // T−3 is P0
        #expect(agenda.cue(now: at(15, 4)) == .imminent(review))
        #expect(agenda.cue(now: at(15, 5)) == nil)
        #expect(agenda.nextCueChange(after: at(14, 0)) == at(14, 50))
        #expect(agenda.nextCueChange(after: at(14, 50)) == at(14, 57))
        #expect(agenda.nextCueChange(after: at(15, 5)) == nil)
    }

    @Test func aLongMeetingDoesNotHideTheNextOne() {
        let long = event("Workshop", at(13, 0), minutes: 180)
        let next = event("Call", at(14, 0))
        #expect(Agenda(events: [long, next], reminders: []).cue(now: at(13, 55)) == .headsUp(next))
    }

    @Test func briefLineAndJoinLinks() {
        let agenda = Agenda(events: [event("A", at(10, 0)), event("B", at(16, 0)), event("C", at(9, 0, day: 12))],
                            reminders: [AgendaReminder(id: "1", title: "x", due: nil), AgendaReminder(id: "2", title: "y", due: nil)])
        #expect(agenda.briefLine(now: at(7, 0), calendar: cal).hasPrefix("2 meetings · first at "))
        #expect(agenda.briefLine(now: at(7, 0), calendar: cal).hasSuffix(" · 2 reminders"))
        #expect(Agenda.empty.briefLine(now: at(7, 0), calendar: cal) == "No meetings today")
        let zoom = AgendaEvent(extID: "z", title: "Z", start: at(9, 0), end: at(10, 0), location: " https://zoom.us/j/1 ")
        #expect(zoom.joinURL?.host() == "zoom.us")
        #expect(AgendaEvent(extID: "r", title: "R", start: at(9, 0), end: at(10, 0), location: "Room 4").joinURL == nil)
    }

    @Test func tasksAndRemindersDueSoonSpeakLikeMeetings() {
        let task = DueItem(id: "t1", title: "Pay rent", due: at(0, 38, day: 12))
        let agenda = Agenda(events: [], reminders: [AgendaReminder(id: "r1", title: "Call bank", due: at(17, 0, day: 12))])
        let now = at(0, 18, day: 12)
        #expect(agenda.statusLine(now: now, tasks: [task], calendar: cal) == "Pay rent in 20 min")
        #expect(agenda.statusLine(now: at(0, 38, day: 12), tasks: [task], calendar: cal) == "Pay rent now")
        #expect(agenda.statusLine(now: at(9, 0, day: 12), tasks: [task], calendar: cal) == "2 due today") // one overdue, one later
        #expect(agenda.cue(now: at(0, 27, day: 12), tasks: [task]) == nil)
        #expect(agenda.cue(now: at(0, 28, day: 12), tasks: [task]) == .dueSoon(task)) // T−10: mint eyes, one peek
        #expect(agenda.cue(now: at(0, 37, day: 12), tasks: [task]) == .dueSoon(task))
        #expect(agenda.cue(now: at(0, 38, day: 12), tasks: [task]) == .due(task))
        #expect(agenda.cue(now: at(0, 43, day: 12), tasks: [task]) == nil) // 5 min later it's done speaking
        #expect(agenda.nextCueChange(after: at(0, 0, day: 12), tasks: [task]) == at(0, 28, day: 12))
        #expect(agenda.nextCueChange(after: at(0, 28, day: 12), tasks: [task]) == at(0, 38, day: 12))
    }

    @Test func onlyRemindersWithADueDateTodayOrEarlierCount() {
        let list = [AgendaReminder(id: "undated", title: "u", due: nil),
                    AgendaReminder(id: "today", title: "t", due: at(18, 0)),
                    AgendaReminder(id: "overdue", title: "o", due: at(9, 0, day: 9)),
                    AgendaReminder(id: "tomorrow", title: "m", due: at(9, 0, day: 12))]
        #expect(AgendaReminder.dueToday(list, now: at(10, 0), calendar: cal).map(\.id) == ["today", "overdue"])
    }

    @Test func eventsAreSortedAndOngoingCountsAsNext() {
        let agenda = Agenda(events: [event("B", at(11, 0)), event("A", at(10, 0), minutes: 90)], reminders: [])
        #expect(agenda.events.map(\.title) == ["A", "B"])
        #expect(agenda.next(after: at(11, 15))?.title == "A") // A runs until 11:30
    }
}

@Suite struct ApprovalTests {
    /// Must match approvalMessage() in backend/supabase/functions/approve/index.ts byte for byte.
    @Test func approvalMessageFormat() {
        let message = BlinkAction.approvalMessage(actionID: "3f2a-id", payloadHash: "\\xABCDEF", expires: 1791720000)
        #expect(String(decoding: message, as: UTF8.self) == "blink-approve:v1\n3f2a-id\nabcdef\n1791720000")
    }

    @Test func decodesAnActionRow() throws {
        let json = #"{"id":"a1","kind":"reminder.add","risk":"amber","payload_hash":"\\x01","payload":{"title":"Add reminder?","summary":"Tomorrow","verb":"Add reminder","due":"2026-10-12T09:00:00Z"}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let action = try decoder.decode(BlinkAction.self, from: Data(json.utf8))
        #expect(action.risk == .amber && action.payload.verb == "Add reminder" && action.payload.due != nil)
    }
}

@Suite struct ItemTests {
    @Test func refreshNeverOverwritesUnsavedWriting() {
        let server = [BlinkItem(id: "a", type: .note, title: "A", body: "old"), BlinkItem(id: "b", type: .note, title: "B")]
        let local = [BlinkItem(id: "a", type: .note, title: "A", body: "typed but not saved"),
                     BlinkItem(id: "c", type: .task, title: "new, not saved")]
        let merged = BlinkItem.merge(server: server, local: local, unsaved: ["a", "c"])
        #expect(merged.first { $0.id == "a" }?.body == "typed but not saved")
        #expect(merged.contains { $0.id == "b" })
        #expect(merged.contains { $0.id == "c" })
        // Saved items follow the server.
        #expect(BlinkItem.merge(server: server, local: local, unsaved: []).first { $0.id == "a" }?.body == "old")
    }

    @Test func dueTodayIncludesOverdueButNotTomorrowOrDone() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10))!
        func task(_ hours: Double, _ status: BlinkItem.Status = .open) -> BlinkItem {
            BlinkItem(id: "\(hours)", type: .task, title: "t", status: status, dueAt: now.addingTimeInterval(hours * 3600))
        }
        #expect(task(5).isDue(by: now, calendar: cal))       // later today
        #expect(task(-30).isDue(by: now, calendar: cal))     // overdue
        #expect(!task(15).isDue(by: now, calendar: cal))     // tomorrow 01:00
        #expect(!task(1, .done).isDue(by: now, calendar: cal))
        #expect(!BlinkItem(id: "n", type: .note, title: "n", dueAt: now).isDue(by: now, calendar: cal))
    }
}

@Suite struct TaskInputTests {
    @Test func readsTheDateAndKeepsTheTitle() throws {
        let cal = Calendar.current
        let parsed = TaskInput.parse("Send invoice tomorrow at 10am")
        #expect(parsed.title == "Send invoice")
        let due = try #require(parsed.due)
        #expect(cal.isDate(due, inSameDayAs: cal.date(byAdding: .day, value: 1, to: .now)!))
        #expect(cal.component(.hour, from: due) == 10)
    }

    @Test func plainTextHasNoDate() {
        #expect(TaskInput.parse("  Buy milk ") == ("Buy milk", nil))
        let lastYear = TaskInput.parse("Notes from 3 March 2020")
        #expect(lastYear.title == "Notes from 3 March 2020" && lastYear.due == nil)
    }
}

@Suite struct HabitTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        c.firstWeekday = 2 // weeks start Monday
        return c
    }()
    /// Mon 12 Oct 2026 is the reference "today".
    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!)!
    }
    private func answers(_ pairs: [(Int, HabitAnswer)]) -> [String: HabitAnswer] {
        Dictionary(uniqueKeysWithValues: pairs.map { (HabitDay.key(day($0.0), calendar: cal), $0.1) })
    }
    private let daily = Habit(id: "h", name: "Read", createdAt: Date(timeIntervalSince1970: 1_700_000_000))

    @Test func countsDoneDaysAndWaitsForToday() {
        #expect(daily.progress(answers: answers([(0, .done), (-1, .done), (-2, .done)]), today: day(0), calendar: cal).streak == 3)
        // Today not answered yet: yesterday's run still stands.
        #expect(daily.progress(answers: answers([(-1, .done), (-2, .done)]), today: day(0), calendar: cal).streak == 2)
    }

    @Test func skipsAndRestDaysNeverBreakIt() {
        #expect(daily.progress(answers: answers([(0, .done), (-1, .skipped), (-2, .done)]), today: day(0), calendar: cal).streak == 2)
        let weekdaysOnly = Habit(id: "w", name: "Run", weekdays: [2, 3, 4, 5, 6], createdAt: daily.createdAt)
        // Mon done, Sat/Sun are rest days, Fri done → 2.
        #expect(weekdaysOnly.progress(answers: answers([(0, .done), (-3, .done)]), today: day(0), calendar: cal).streak == 2)
    }

    @Test func oneMissPerWeekIsForgivenTwoAreNot() {
        // Week of 5–11 Oct: one miss on Thu 8th, forgiven.
        let one = answers([(-1, .done), (-2, .done), (-3, .done), (-4, .notToday), (-5, .done), (-6, .done), (-7, .done)])
        // 6 done days; the run ends in the week before, at its second unanswered day.
        #expect(daily.progress(answers: one, today: day(0), calendar: cal).streak == 6)
        // Two misses in that week: the run stops at the second one.
        let two = answers([(-1, .done), (-2, .notToday), (-3, .done), (-4, .notToday), (-5, .done)])
        #expect(daily.progress(answers: two, today: day(0), calendar: cal).streak == 2)
    }

    @Test func keptOutOfSevenAndMilestones() {
        let progress = daily.progress(answers: answers([(0, .done), (-1, .done), (-2, .notToday), (-3, .skipped),
                                                        (-4, .done), (-5, .done), (-6, .done)]), today: day(0), calendar: cal)
        #expect(progress.kept == 5 && progress.of == 6) // the skip isn't counted against you
        let week = answers((0..<7).map { (-$0, .done) })
        #expect(daily.progress(answers: week, today: day(0), calendar: cal).isMilestone)
    }

    @Test func theDayEndsAtWakeTime() {
        let early = cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 6, minute: 30))!
        let later = cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 7, minute: 30))!
        #expect(HabitDay.key(HabitDay.day(for: early, wakeHour: 7, wakeMinute: 0, calendar: cal), calendar: cal) == "2026-10-12")
        #expect(HabitDay.key(HabitDay.day(for: later, wakeHour: 7, wakeMinute: 0, calendar: cal), calendar: cal) == "2026-10-13")
    }
}
