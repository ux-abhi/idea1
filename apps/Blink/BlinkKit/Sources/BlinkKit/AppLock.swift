// © Pexilim
import Foundation
import LocalAuthentication

/// App lock: Face ID / Touch ID with passcode or password fallback (ARCHITECTURE §36.5). A UX gate, not encryption.
public enum AppLock {
    /// Default 5 minutes (ARCHITECTURE §36.5); the user can change it in Settings › Privacy.
    public static let defaultRelockAfter: TimeInterval = 5 * 60

    public static func shouldRelock(awaySince: Date?, now: Date = .now, after: TimeInterval = defaultRelockAfter) -> Bool {
        guard let awaySince else { return false }
        return now.timeIntervalSince(awaySince) >= after
    }

    public enum Result: Sendable { case unlocked, cancelled, unavailable }

    public static func unlock(reason: String) async -> Result {
        let context = LAContext()
        var error: NSError?
        // No passcode or password set: there is nothing to check against, so the gate can't apply.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .unlocked : .cancelled
        } catch {
            return .cancelled
        }
    }
}
