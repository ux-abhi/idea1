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
