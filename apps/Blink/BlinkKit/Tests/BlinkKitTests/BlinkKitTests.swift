// © Pexilim
import Foundation
import LocalAuthentication
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
        let hold = try #require(motion["hold"] as? [String: Any])
        #expect(hold["done"] as? Double == Tokens.Hold.done)
        #expect(hold["celebrate"] as? Double == Tokens.Hold.celebrate)
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

    @Test func heroShowsOneBigNumber() {
        let agenda = Agenda(events: [event("Review", at(15, 0))], reminders: [])
        #expect(agenda.hero(now: at(14, 48), calendar: cal) == ("12 min", "until Review"))
        #expect(agenda.hero(now: at(13, 20), calendar: cal) == ("1 h 40 min", "until Review"))
        #expect(agenda.hero(now: at(15, 2), calendar: cal) == ("Now", "Review"))
        #expect(agenda.hero(now: at(9, 0), calendar: cal).caption == "Next: Review")
        let task = DueItem(id: "t", title: "Pay rent", due: at(18, 0))
        #expect(Agenda.empty.hero(now: at(16, 0), tasks: [task], calendar: cal) == ("1", "due today"))
        #expect(Agenda.empty.hero(now: at(16, 0), calendar: cal).value == "All clear")
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

    @Test func activityStatesWhatHappened() throws {
        func row(_ title: String, _ status: String) throws -> BlinkAction {
            var action = try JSONDecoder().decode(BlinkAction.self, from: Data(
                #"{"id":"a","kind":"reminder.add","risk":"green","payload_hash":"01","payload":{"title":"\#(title)"}}"#.utf8))
            action.status = status
            return action
        }
        #expect(try row("Add reminder “Call Sam”?", "done").historyTitle == "Added reminder “Call Sam”")
        #expect(try row("Mark done: task “Pay”?", "done").historyTitle == "Marked done: task “Pay”")
        #expect(try row("Move reminder “Job” to Mon 17:30?", "declined").historyTitle == "Dismissed: move reminder “Job” to Mon 17:30")
        #expect(try row("Add task “X”?", "failed").historyTitle == "Didn't work: add task “X”")
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

    @Test func answersAreLoadedFromTheDayBeforeTheOldestHabit() {
        let newer = Habit(id: "n", name: "Walk", createdAt: day(-3))
        // 1_700_000_000 is 15 Nov 2023 in Kolkata.
        #expect(HabitDay.answersSince([newer, daily], today: day(0), calendar: cal) == "2023-11-14")
        #expect(HabitDay.answersSince([], today: day(0), calendar: cal) == "2026-10-11")
    }

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

@Suite struct EveningTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()
    private func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }
    private let evening = (hour: 21, minute: 30), wake = (hour: 7, minute: 0)

    @Test func dueFromEveningUntilWakeOncePerDay() {
        #expect(!EveningCheck.isDue(now: at(12, 21, 29), evening: evening, wake: wake, lastDone: nil, calendar: cal))
        #expect(EveningCheck.isDue(now: at(12, 21, 30), evening: evening, wake: wake, lastDone: nil, calendar: cal))
        #expect(EveningCheck.isDue(now: at(13, 1, 0), evening: evening, wake: wake, lastDone: nil, calendar: cal)) // after midnight, before wake
        #expect(!EveningCheck.isDue(now: at(13, 8, 0), evening: evening, wake: wake, lastDone: nil, calendar: cal)) // next day, before evening
        #expect(!EveningCheck.isDue(now: at(12, 22, 0), evening: evening, wake: wake, lastDone: at(12, 21, 45), calendar: cal))
        #expect(EveningCheck.isDue(now: at(13, 21, 40), evening: evening, wake: wake, lastDone: at(12, 21, 45), calendar: cal))
    }

    @Test func tomorrowLine() {
        let agenda = Agenda(events: [AgendaEvent(extID: "a", title: "A", start: at(13, 10), end: at(13, 11)),
                                     AgendaEvent(extID: "b", title: "B", start: at(13, 15), end: at(13, 16))], reminders: [])
        #expect(agenda.dayLine(for: at(13, 0), calendar: cal).hasPrefix("2 meetings · first at "))
        #expect(agenda.dayLine(for: at(14, 0), calendar: cal) == "No meetings")
    }
}

@Suite struct FocusTimerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func countsDownAndPauses() {
        var timer = FocusTimer.focus(now: t0)
        #expect(timer.remaining(now: t0.addingTimeInterval(60)) == 24 * 60)
        timer.pause(now: t0.addingTimeInterval(300))
        #expect(timer.remaining(now: t0.addingTimeInterval(9999)) == 20 * 60) // paused: no time passes
        timer.resume(now: t0.addingTimeInterval(1000))
        #expect(timer.remaining(now: t0.addingTimeInterval(1060)) == 19 * 60)
        timer.add(minutes: 5)
        #expect(timer.remaining(now: t0.addingTimeInterval(1060)) == 24 * 60)
        #expect(!timer.isFinished(now: t0.addingTimeInterval(1060)))
        #expect(timer.isFinished(now: t0.addingTimeInterval(1000 + 25 * 60)))
    }

    @Test func pomodoroCycleAndClock() {
        var phase = FocusTimer.focus(now: t0)
        var kinds: [FocusTimer.Kind] = []
        for _ in 0..<8 {
            phase = phase.next(now: t0)!
            kinds.append(phase.kind)
        }
        #expect(kinds == [.shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus])
        #expect(FocusTimer.timer(minutes: 5, now: t0).next(now: t0) == nil)
        #expect(FocusTimer.clock(1122) == "18:42" && FocusTimer.clock(3725) == "1:02:05")
    }
}

@Suite struct ClipboardTests {
    @Test func newestFirstRepeatsMoveUpAndTheListStaysCapped() {
        var history = ClipboardHistory()
        history.add(.text("a"))
        history.add(.text("b"))
        history.add(.text("a"))
        #expect(history.items.map(\.text) == ["a", "b"])
        history.add(.text("   "))
        #expect(history.items.count == 2) // blank copies are ignored
        for i in 0..<60 { history.add(.text("item \(i)")) }
        #expect(history.items.count == ClipboardHistory.limit && history.items.first?.text == "item 59")
        #expect(history.search("ITEM 5").map(\.text).first == "item 59")
        history.add(.text(String(repeating: "x", count: ClipboardHistory.maxText + 1)))
        #expect(history.items.first?.text == "item 59") // over 1 MB of text is not kept
    }

    @Test func linksAreRecognisedAndSecretsAreNeverRecorded() {
        #expect(ClipItem.text("https://blink.app/x").kind == .link)
        #expect(ClipItem.text("see https://blink.app").kind == .text)
        #expect(ClipboardHistory.shouldRecord(types: ["public.utf8-plain-text"]))
        #expect(!ClipboardHistory.shouldRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(!ClipboardHistory.shouldRecord(types: ["org.nspasteboard.TransientType"]))
        // Files beat their names; selected words beat the picture of them; a web image beats its address.
        #expect(ClipItem.pick(files: ["/a.pdf"], text: "a.pdf", hasImage: false) == .file)
        #expect(ClipItem.pick(files: [], text: "Hello", hasImage: true) == .text)
        #expect(ClipItem.pick(files: [], text: "https://x.com/cat.png", hasImage: true) == .image)
        #expect(ClipItem.pick(files: [], text: "https://x.com", hasImage: false) == .link)
        #expect(ClipItem.pick(files: [], text: nil, hasImage: false) == nil)
    }
}

@Test func timerTakesTheEarsOnlyInCalmMoods() {
    #expect(Mood.idle.letsTimerShow && Mood.sleepy.letsTimerShow)
    #expect(!Mood.headsUp.letsTimerShow && !Mood.thinking.letsTimerShow && !Mood.done.letsTimerShow)
}

@Test func habitAddedAfterMidnightCountsForTheRunningHabitDay() {
    let cal = Calendar(identifier: .gregorian)
    let sunday = cal.date(from: DateComponents(year: 2026, month: 10, day: 11))!
    let createdMondayNight = cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 1))!
    let habit = Habit(id: "h", name: "Read", weekdays: Array(1...7), createdAt: createdMondayNight)
    let progress = habit.progress(answers: [HabitDay.key(sunday, calendar: cal): .done], today: sunday, calendar: cal)
    #expect(progress.streak == 1)
    // Next habit day, not answered yet: yesterday's done still counts.
    let monday = cal.date(byAdding: .day, value: 1, to: sunday)!
    #expect(habit.progress(answers: [HabitDay.key(sunday, calendar: cal): .done], today: monday, calendar: cal).streak == 1)
}

@Test func dayPlanPutsTodayOnOneAxis() {
    let cal = Calendar(identifier: .gregorian)
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    let now = at(12, 11)
    let plan = DayPlan(
        events: [AgendaEvent(extID: "m", title: "Standup", start: at(12, 10, 30), end: at(12, 11, 30)),
                 AgendaEvent(extID: "t", title: "Tomorrow", start: at(13, 9), end: at(13, 10))],
        tasks: [DueItem(id: "t1", title: "Invoice", due: at(12, 15)), DueItem(id: "t0", title: "Old", due: at(10, 9))],
        reminders: [AgendaReminder(id: "r1", title: "Call", due: at(12, 9)), AgendaReminder(id: "r2", title: "Any", due: at(12, 0)),
                    AgendaReminder(id: "r3", title: "Undated", due: nil)],
        now: now, calendar: cal)
    #expect(plan.overdue.map(\.title) == ["Old"])
    #expect(plan.anytime.map(\.title) == ["Any"])
    #expect(plan.timed.map(\.title) == ["Call", "Standup", "Invoice"])
    #expect(plan.nowIndex == 2) // after the meeting under way, before the 15:00 task
}

@Test func spaceProgressCountsOnlyItsTasks() throws {
    let items = [BlinkItem(id: "1", type: .task, title: "a", status: .done, spaceID: "s"),
                 BlinkItem(id: "2", type: .task, title: "b", spaceID: "s"),
                 BlinkItem(id: "3", type: .note, title: "n", spaceID: "s"),
                 BlinkItem(id: "4", type: .task, title: "other", status: .done)]
    #expect(Space.progress(of: items, in: "s") == (1, 2))
    // A cleared due date goes to the server as null, so the old date is really removed.
    let json = String(decoding: try JSONEncoder().encode(Space(id: "s", title: "Web")), as: UTF8.self)
    #expect(json.contains("\"due_at\":null"))
}

@Test func dueGroupSortsByWhenItIsDue() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 13))!
    #expect(DueGroup.of(nil, now: now, calendar: cal) == .someday)
    #expect(DueGroup.of(now.addingTimeInterval(-60), now: now, calendar: cal) == .overdue)
    #expect(DueGroup.of(cal.startOfDay(for: now), now: now, calendar: cal) == .today) // all-day reminder
    #expect(DueGroup.of(now.addingTimeInterval(3600 * 10), now: now, calendar: cal) == .today) // 23:00
    #expect(DueGroup.of(now.addingTimeInterval(3600 * 11), now: now, calendar: cal) == .upcoming) // midnight
}

@Test func chatHistoryStartsWithTheOwner() {
    let turns: [BlinkServer.ChatTurn] = [.init(role: .assistant, text: "What should I add?")]
        + (0..<20).map { .init(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "\($0)") }
    let sent = BlinkServer.recent([.init(role: .user, text: "first")] + turns)
    #expect(sent.first?.role == .user && sent.count <= 20)
}

@Test func contentLintBlocksPlaceholdersAndLongPosts() throws {
    func piece(_ platform: ContentPiece.Platform, body: String, parts: [String] = [], tags: [String] = []) throws -> ContentPiece {
        let json = #"{"id":"p","idea":"i","platform":"\#(platform.rawValue)","format":"post","hook":"","body":"","parts":[],"hashtags":[],"status":"drafted","lint_score":null,"published_at":null,"created_at":"2026-10-12T08:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var p = try decoder.decode(ContentPiece.self, from: Data(json.utf8))
        p.body = body
        p.parts = parts
        p.hashtags = tags
        return p
    }
    #expect(ContentLint.check(try piece(.linkedin, body: "Shipped Blink's timeline today. What would you add?")).score == 100)
    #expect(ContentLint.check(try piece(.linkedin, body: "Thanks [client name] for the help")).issues.contains { $0.blocks })
    #expect(ContentLint.check(try piece(.x, body: "short", parts: ["ok", String(repeating: "a", count: 281)])).issues
        .contains { $0.message == "Post 2 is over 280 characters" && $0.blocks })
    let soft = ContentLint.check(try piece(.instagram, body: "Let's delve into it", tags: ["a", "b", "c", "d", "e", "f"]), neverSay: ["it"])
    #expect(soft.score == 70 && !soft.issues.contains { $0.blocks })
    #expect(try piece(.x, body: "first", parts: ["1/", "2/"], tags: []).postText == "1/\n\n2/")
}

@Test func modelListMatchesTheServer() throws {
    // The server's allowlist (backend/supabase/functions/_shared/models.ts) must offer every model Settings shows.
    let url = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../../backend/supabase/functions/_shared/models.ts").standardized
    let server = try String(contentsOf: url, encoding: .utf8)
    for model in AIModel.all { #expect(server.contains("id: \"\(model.id)\""), "\(model.id) missing on the server") }
}

@Test func modelShortNamesFitSmallPlaces() {
    let names = Dictionary(uniqueKeysWithValues: AIModel.all.map { ($0.id, $0.shortName) })
    #expect(names["claude-opus-5-5"] == "Opus 5.5")
    #expect(names["openai/gpt-oss-120b"] == "GPT-OSS 120B")
    #expect(names["minimaxai/minimax-m2.7"] == "MiniMax M2.7")
    #expect(AIModel.all.first { $0.id == "moonshotai/kimi-k3" }?.group == .best)
}

@Test func quickCommandsParseInTheNotch() throws {
    let cal = Calendar.current
    // The system's date reader resolves "tomorrow" from the real clock, so the test does too.
    let now = Date.now
    guard case .task(let title, let due)? = QuickCommand.parse("/task Send invoice tomorrow at 10", now: now) else {
        Issue.record("task not parsed"); return
    }
    let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
    #expect(title == "Send invoice" && due.map { cal.isDate($0, inSameDayAs: tomorrow) } == true)
    #expect(QuickCommand.parse("/remind Call Sam", now: now) == .remind(title: "Call Sam", due: nil))
    #expect(QuickCommand.parse("/timer 10m") == .timer(minutes: 10))
    #expect(QuickCommand.parse("/timer 1.5h") == .timer(minutes: 90))
    #expect(QuickCommand.parse("/timer 0") == nil && QuickCommand.parse("/task ") == nil && QuickCommand.parse("what's left today?") == nil)
    #expect(QuickCommand.suggestions(for: "/re").map(\.name) == ["/remind"])
    #expect(QuickCommand.parse("/post Why onboarding fails") == .post(idea: "Why onboarding fails"))
    #expect(QuickCommand.parse("/post") == nil && QuickCommand.parse("/ideas") == .ideas(theme: ""))
    #expect(QuickCommand.suggestions(for: "/task pay").isEmpty)
}

@Test func laterOffersSensibleTimes() {
    let cal = Calendar(identifier: .gregorian)
    let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10))! // a Monday
    #expect(Later.choices(now: morning, calendar: cal).map(\.title) == ["In 1 hour", "This evening, 18:00", "Tomorrow, 9:00", "Next Monday, 9:00"])
    let late = cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 17, minute: 30))!
    #expect(!Later.choices(now: late, calendar: cal).contains { $0.title.hasPrefix("This evening") })
}

@Test func weekPlanDaysAreTheNextSeven() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 12, day: 29, hour: 23))!
    #expect(HabitDay.nextDays(from: now, calendar: cal) == ["2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01",
                                                             "2027-01-02", "2027-01-03", "2027-01-04"])
}

@Test func mailOpensInAppleMailByMessageID() throws {
    let json = #"{"id":"e1","account":"gmail","message_id":"<abc@tv.com>","from_name":"","from_addr":"w@tv.com","subject":"Interview","received_at":null,"triage":"important","reason":"Interview invite","summary":"s","needs_reply":true,"status":"new","created_at":"2026-10-12T10:00:00Z"}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let mail = try decoder.decode(EmailMessage.self, from: Data(json.utf8))
    #expect(mail.sender == "w@tv.com" && mail.triage == .important)
    #expect(mail.mailURL?.absoluteString == "message://%3Cabc%40tv%2Ecom%3E")
}

@Test func replyNeedsOnePlainRecipientAndScheduledSendsDecode() throws {
    var draft = MailDraft(emailID: "e1", account: "icloud", from: "hello@example.com", to: "w@tv.com", subject: "Re: Hi",
                          body: "Thanks", inReplyTo: "<a@tv.com>", messageID: "<b@pexilim.com>")
    #expect(draft.hasValidRecipient)
    for bad in ["w@tv.com, x@y.com", "Wolfram <w@tv.com>", "w@tv", ""] {
        draft.to = bad
        #expect(!draft.hasValidRecipient, "\(bad) accepted")
    }
    let json = #"{"id":"a1","kind":"mail.send","risk":"red","payload_hash":"\\x01","payload":{"title":"Send reply?","subject":"Re: Hi","to":"w@tv.com","email_id":"e1","send_at":"2026-10-15T07:00:00Z"}}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let action = try decoder.decode(BlinkAction.self, from: Data(json.utf8))
    #expect(action.payload.sendAt == Date(timeIntervalSince1970: 1_792_047_600) && action.payload.emailID == "e1")
}

@Test func touchIDCancelStaysQuietButOtherFailuresSaySo() {
    #expect(ApprovalKey.Problem.from(LAError(.userCancel)) == .cancelled)
    #expect(ApprovalKey.Problem.from(LAError(.systemCancel)) == .cancelled)
    #expect(ApprovalKey.Problem.from(LAError(.biometryLockout)) == .unavailable)
    #expect(ApprovalKey.Problem.cancelled.message.isEmpty && !ApprovalKey.Problem.keyInvalid.message.isEmpty)
}

@Test func dayOnlyRemindersNeverCueAndLaterCuesAgain() {
    let cal = Calendar(identifier: .gregorian)
    let day = AgendaReminder.due(from: DateComponents(year: 2026, month: 10, day: 12), calendar: cal)
    #expect(day.date != nil && !day.timed)
    let agenda = Agenda(events: [], reminders: [AgendaReminder(id: "r1", title: "Pay rent", due: day.date, timed: day.timed)])
    #expect(agenda.dueItems().isEmpty)
    let now = Date(timeIntervalSince1970: 1_791_800_000)
    let item = DueItem(id: "t1", title: "Call", due: now)
    #expect(MeetingCue.due(item).id != MeetingCue.due(DueItem(id: "t1", title: "Call", due: now + 1800)).id)
}

@Test func moneyTotalsAreExactPerCategoryAndMonth() throws {
    let json = #"[{"id":"1","amount":8.1,"note":"Lunch","category":"food","spent_on":"2026-10-12"},{"id":"2","amount":0.2,"note":"Coffee","category":"food","spent_on":"2026-10-12"},{"id":"3","amount":23.4,"note":"Rewe","category":"groceries","spent_on":"2026-10-01"},{"id":"4","amount":99,"note":"Old","category":"fun","spent_on":"2026-09-30"}]"#
    let spends = try JSONDecoder().decode([Spend].self, from: Data(json.utf8))
    let totals = MoneyMath.totals(spends, month: "2026-10")
    #expect(totals.map(\.category) == [.groceries, .food])
    #expect(totals.first { $0.category == .food }?.total == Decimal(string: "8.3"))
    #expect(MoneyMath.total(spends, month: "2026-10") == Decimal(string: "31.7"))
    #expect(MoneyMath.used(Decimal(250), of: Decimal(200)) == 1.25)
}

@Test func spentNeedsAnAmount() {
    #expect(QuickCommand.parse("/spent 8.50 lunch, 3 bus") == .spent("8.50 lunch, 3 bus"))
    #expect(QuickCommand.parse("/spent lunch") == nil)
}

@Test func typedAmountsParseWithCommaOrDot() {
    #expect(MoneyMath.parseAmount("8,50") == Decimal(string: "8.5"))
    #expect(MoneyMath.parseAmount("€ 12.345") == nil) // ambiguous: never 12.35 or 12,345
    #expect(MoneyMath.parseAmount("1.234,56") == Decimal(string: "1234.56") && MoneyMath.parseAmount("1250.40") == Decimal(string: "1250.4"))
    #expect(MoneyMath.parseAmount("-5") == nil)
    #expect(MoneyMath.parseAmount("1.2.3") == nil)
    #expect(MoneyMath.parseAmount("0") == nil && MoneyMath.parseAmount("") == nil)
}

@Test func monthSummaryComparesLikeWithLike() throws {
    let cal = Calendar(identifier: .gregorian)
    let json = #"[{"id":"1","amount":10,"note":"a","category":"food","spent_on":"2026-10-01"},{"id":"2","amount":20,"note":"b","category":"food","spent_on":"2026-10-04"},{"id":"3","amount":15,"note":"c","category":"fun","spent_on":"2026-09-02"},{"id":"4","amount":100,"note":"d","category":"housing","spent_on":"2026-09-20"}]"#
    let spends = try JSONDecoder().decode([Spend].self, from: Data(json.utf8))
    let s = MoneyMath.summary(spends, today: "2026-10-04", calendar: cal)
    #expect(s.total == 30 && s.today == 20 && s.average == Decimal(string: "7.5") && s.forecast == Decimal(string: "232.5"))
    #expect(s.lastMonthSoFar == 15 && s.lastMonthTotal == 115 && s.change == 1.0)
    #expect(MoneyMath.cumulative(MoneyMath.daily(spends, month: "2026-10", calendar: cal)).prefix(4) == [10, 10, 10, 30])
    #expect(MoneyMath.previous(month: "2026-01") == "2025-12" && MoneyMath.daysIn(month: "2026-02", calendar: cal) == 28)
}

@Test func accountBalancesTakeOffSpendsEnteredSinceTheyWereSet() throws {
    let json = #"{"id":"a1","name":"Sparkasse","kind":"checking","balance":1000,"balance_at":"2026-10-01T10:00:00Z","is_default":true,"spent_since":23.4}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let account = try decoder.decode(MoneyAccount.self, from: Data(json.utf8))
    #expect(MoneyMath.balance(of: account) == Decimal(string: "976.6"))
    var fresh = account
    fresh.spentSince = nil
    #expect(MoneyMath.totalBalance([account, fresh]) == Decimal(string: "1976.6"))
    let summary = MoneyMath.Summary(total: 100, today: 10, average: 10, forecast: 310, lastMonthSoFar: 0, lastMonthTotal: 0)
    #expect(MoneyMath.leftAtMonthEnd(total: 500, summary: summary, today: "2026-10-21", calendar: Calendar(identifier: .gregorian)) == 400)
    #expect(MoneyMath.runwayDays(total: 500, average: 10) == 50 && MoneyMath.runwayDays(total: 500, average: 0) == nil)
}

@Test func balancesParseGermanAndEnglishStyleAndNegatives() {
    #expect(MoneyMath.parseBalance("1.234,56") == Decimal(string: "1234.56"))
    #expect(MoneyMath.parseBalance("1250.40") == Decimal(string: "1250.4"))
    #expect(MoneyMath.parseBalance("-50") == -50 && MoneyMath.parseBalance("0") == 0)
    #expect(MoneyMath.parseBalance("") == nil && MoneyMath.parseBalance("abc") == nil)
    #expect(MoneyMath.parseBalance("1.250") == nil && MoneyMath.parseBalance("1,234.56") == nil)
}

@Test func contentStatsComparePostsAndFormats() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let day: (Int) -> Date = { cal.date(from: DateComponents(year: 2026, month: 10, day: $0, hour: 12))! }
    let posts = [
        PagePost(url: "a", kind: .video, caption: "", likes: 100, comments: 20, views: 5000, postedAt: day(12)),   // Mon
        PagePost(url: "b", kind: .carousel, caption: "", likes: 300, comments: 60, views: nil, postedAt: day(10)), // Sat
        PagePost(url: "c", kind: .image, caption: "", likes: 40, comments: nil, views: nil, postedAt: day(5)),     // Mon
        PagePost(url: "d", kind: .video, caption: "", likes: 60, comments: 0, views: 3000, postedAt: day(1)),      // Thu
    ]
    let s = ContentStats.summary(posts, count: 2)
    #expect(s.posts == 2 && s.averageLikes == 200 && s.averageComments == 40 && s.averageReelViews == 5000)
    #expect(s.change == 3.8) // (120+360)/2 = 240 against (40+60)/2 = 50: (240 - 50) / 50
    #expect(ContentStats.summary(posts, count: 3).change == nil) // 3 newest against only 1 older: no trend
    #expect(ContentStats.byFormat(posts).map(\.kind) == [.carousel, .video, .image])
    #expect(ContentStats.byFormat(posts).first { $0.kind == .video }?.views == 4000)
    #expect(ContentStats.byWeekday(posts, calendar: cal).first { $0.weekday == 2 }?.engagement == 80) // Mondays: 120 and 40
    #expect(ContentStats.top(posts, count: 1).first?.url == "b")
    #expect(ContentStats.perWeek(posts, weeks: 3, now: day(12), calendar: cal) == [1, 2, 1])
}

@Test func setupStepsKnowWhatIsMissing() {
    let fresh = SetupStep.all(keys: ["groq": "missing", "anthropic": "missing"], calendarGranted: false, voicePage: "",
                              mailConnected: false, hasAccount: false, hasHabit: false)
    #expect(fresh.filter(\.done).isEmpty && fresh.first?.id == .aiKey)
    let ready = SetupStep.all(keys: ["groq": "ok"], calendarGranted: true, voicePage: "@yourname on Instagram",
                              mailConnected: true, hasAccount: true, hasHabit: true)
    #expect(ready.allSatisfy { $0.done })
    // A provider that's briefly unreachable still has a key.
    #expect(SetupStep.all(keys: ["groq": "unreachable", "anthropic": "missing"], calendarGranted: true, voicePage: "",
                          mailConnected: true, hasAccount: true, hasHabit: true).first { $0.id == .aiKey }?.done == true)
    // A key the provider refused doesn't count.
    #expect(SetupStep.all(keys: ["groq": "rejected", "anthropic": "missing"], calendarGranted: true, voicePage: "",
                          mailConnected: true, hasAccount: true, hasHabit: true).first { $0.id == .aiKey }?.done == false)
    // While the key check hasn't answered, don't nag about keys.
    #expect(SetupStep.all(keys: nil, calendarGranted: true, voicePage: "", mailConnected: true, hasAccount: true, hasHabit: true)
        .first { $0.id == .aiKey }?.done == true)
}

@Test func setupProgressResumesAndResets() {
    let defaults = UserDefaults(suiteName: "blink.tests.setup.\(UUID().uuidString)")!
    let progress = ServerSetup.Progress(defaults: defaults)
    progress.ref = "abc"
    progress.markDone("mailSchedule")
    #expect(ServerSetup.Progress(defaults: defaults).ref == "abc" && progress.done("mailSchedule") && !progress.done("cleanupSchedule"))
    progress.reset() // a stale project: start over
    #expect(progress.ref == nil && !progress.done("mailSchedule") && !progress.ownerCreated)
}

@Test func serverSetupBasics() {
    // RFC 7636 appendix B: this verifier gives this S256 challenge.
    #expect(ServerSetup.PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    let pkce = ServerSetup.PKCE()
    #expect(pkce.verifier.count >= 43 && pkce.challenge.count == 43 && !pkce.state.isEmpty)
    #expect(ServerSetup.region(for: "Asia/Kolkata") == "ap-south-1" && ServerSetup.region(for: "Europe/Berlin") == "eu-central-1")
    #expect(ServerSetup.region(for: "America/New_York") == "us-east-1")
    let fns = ServerSetup.installable(["chat", "_shared", "signin", "mail", "money", "mail-probe", "capture"])
    #expect(fns.map(\.slug) == ["capture", "chat", "mail", "money"])
    #expect(fns.filter { !$0.verifyJWT }.map(\.slug) == ["capture", "mail"])
    // Queries stay queries (appending a "?" to the path would encode it, and Supabase would answer 404).
    let api = ServerSetup.Client(token: "t")
    #expect(api.url("projects/abc/api-keys", query: [URLQueryItem(name: "reveal", value: "true")]).absoluteString
            == "https://api.supabase.com/v1/projects/abc/api-keys?reveal=true")
    #expect(api.url("projects/abc/health", query: [URLQueryItem(name: "services", value: "db,auth,rest")]).absoluteString
            == "https://api.supabase.com/v1/projects/abc/health?services=db,auth,rest")
}

@Test func migrationsApplyWithTheirLedgerRow() {
    let m = ServerSetup.Migration(fileName: "20261012130000_money_accounts.sql")
    #expect(m?.version == "20261012130000" && m?.name == "money_accounts")
    #expect(ServerSetup.Migration(fileName: "notes.txt") == nil && ServerSetup.Migration(fileName: "x'; drop table y;--.sql") == nil)
    let sql = m!.wrapped("create table t ();")
    #expect(sql.hasPrefix("begin;") && sql.hasSuffix("commit;") && sql.contains("values ('20261012130000', 'money_accounts')"))
}

@Test func captureTokensAreRandomAndOnlyTheirHashIsKept() {
    let a = CaptureToken.make(), b = CaptureToken.make()
    #expect(a.token != b.token && a.token.hasPrefix("blk_") && a.token.count == 47)
    #expect(a.token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
    // SHA-256 of "abc", as Postgres bytea text.
    #expect(CaptureToken.hash(of: "abc") == "\\xba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(a.hash == CaptureToken.hash(of: a.token) && a.hash.count == 66)
}

@Test func keychainRoundTripsWithoutAnAppID() throws {
    // Tests run unsigned, like the free DMG: no keychain-access-groups, so this exercises the login-keychain path.
    #expect(Keychain.dataProtection == false)
    let keychain = Keychain(service: "blink.tests.\(UUID().uuidString)")
    try keychain.set(Data("secret".utf8), for: "session")
    #expect(try keychain.data(for: "session") == Data("secret".utf8))
    try keychain.set(Data("newer".utf8), for: "session")
    #expect(try keychain.data(for: "session") == Data("newer".utf8))
    try keychain.remove("session")
    #expect(try keychain.data(for: "session") == nil)
}

@Test func moneyAlertsAt80And100PercentOnceEach() throws {
    let json = """
    [{"id":"a","amount":170,"note":"Rewe","category":"groceries","spent_on":"2026-10-03"},
     {"id":"b","amount":40,"note":"Lunch","category":"food","spent_on":"2026-10-04"},
     {"id":"c","amount":65,"note":"Cinema","category":"fun","spent_on":"2026-10-05"},
     {"id":"d","amount":500,"note":"Old","category":"food","spent_on":"2026-09-30"}]
    """
    let spends = try JSONDecoder().decode([Spend].self, from: Data(json.utf8))
    let budgets = [Budget(category: .groceries, monthlyLimit: 200), Budget(category: .food, monthlyLimit: 250), Budget(category: .fun, monthlyLimit: 60)]
    let alerts = MoneyAlerts.crossed(spends, budgets: budgets, month: "2026-10", told: [])
    // Groceries 85% (warn), food 16% (quiet; September doesn't count), fun 108% (over, and not also an 80% alert).
    #expect(alerts.map(\.key) == ["2026-10:groceries:80", "2026-10:fun:100"])
    #expect(alerts.first?.text.contains("85%") == true && alerts.last?.over == true)
    #expect(MoneyAlerts.crossed(spends, budgets: budgets, month: "2026-10", told: Set(alerts.map(\.key))).isEmpty)
}

@Test func lastWeekSummaryCoversMondayToSunday() throws {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let json = """
    [{"id":"a","amount":30,"note":"Rewe","category":"groceries","spent_on":"2026-10-05"},
     {"id":"b","amount":12,"note":"Lunch","category":"food","spent_on":"2026-10-11"},
     {"id":"c","amount":99,"note":"This week","category":"fun","spent_on":"2026-10-12"},
     {"id":"d","amount":99,"note":"Week before","category":"fun","spent_on":"2026-10-04"}]
    """
    let spends = try JSONDecoder().decode([Spend].self, from: Data(json.utf8))
    // Tuesday 13 Oct: last week is Mon 5 – Sun 11 Oct.
    let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9))!
    let week = try #require(MoneyAlerts.lastWeek(spends, today: today, calendar: cal))
    let total = Decimal(42).formatted(.currency(code: MoneyMath.currency))
    #expect(week.text == "Last week: \(total). Groceries \(Decimal(30).formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0)))), \(SpendCategory.food.title) \(Decimal(12).formatted(.currency(code: MoneyMath.currency).precision(.fractionLength(0)))).")
    #expect(MoneyAlerts.lastWeek([], today: today, calendar: cal) == nil)
}

@Test func replyDigestShowsOnceADayFromTen() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let nine = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9, minute: 59))!
    let ten = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10, minute: 0))!
    #expect(!ReplyDigest.due(now: nine, shownOn: nil, waiting: 3, calendar: cal))
    #expect(ReplyDigest.due(now: ten, shownOn: "2026-10-13", waiting: 3, calendar: cal))
    #expect(!ReplyDigest.due(now: ten, shownOn: "2026-10-14", waiting: 3, calendar: cal))
    #expect(!ReplyDigest.due(now: ten, shownOn: nil, waiting: 0, calendar: cal))
    #expect(ReplyDigest.nextTime(after: nine, calendar: cal) == ten && ReplyDigest.nextTime(after: ten, calendar: cal) == nil)
    #expect(ReplyDigest.text(1).contains("1 email is") && ReplyDigest.text(3).contains("3 emails are"))
}

@Test func chatStreamEventsParse() {
    typealias E = BlinkServer.ChatEvent
    #expect(E.parse(line: #"data: {"t":"delta","text":"Hi "}"#) == .delta("Hi "))
    #expect(E.parse(line: #"data: {"t":"reset"}"#) == .reset)
    #expect(E.parse(line: #"data: {"t":"done","reply":"Added.","proposed":1}"#) == .done(reply: "Added.", proposed: 1))
    #expect(E.parse(line: #"data: {"t":"error","error":"No key."}"#) == .failed("No key."))
    #expect(E.parse(line: "") == nil && E.parse(line: ": keep-alive") == nil && E.parse(line: #"data: {"t":"other"}"#) == nil)
}

@Test func moneyAlertMemoryStaysSmallAndCurrent() {
    let old: Set<String> = ["2026-09:food:80", "week-2026-9", "week-2026-41", "week-2025-52", "2026-10:fun:100"]
    let kept = MoneyAlerts.remember(old, adding: ["2026-10:groceries:80"], month: "2026-10")
    // Last month's keys go; only the newest week (by number: 41 beats 9) stays.
    #expect(kept == ["2026-10:fun:100", "2026-10:groceries:80", "week-2026-41"])
}

@Test func clearCommandClearsTheChat() {
    #expect(QuickCommand.parse("/clear") == .clear && QuickCommand.parse("  /CLEAR ") == .clear)
    #expect(QuickCommand.suggestions(for: "/cl").map(\.name) == ["/clear"])
}
