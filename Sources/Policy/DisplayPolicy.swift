import Foundation

struct DisplayPolicy {
    var enabled = true
    var delay: TimeInterval = 15
    var lockedSince: TimeInterval?
    var blocked = false
    private(set) var sleepHandled = false
    private var displayAsleep = false

    mutating func reset() {
        sleepHandled = false
        blocked = false
    }

    mutating func clearLockSession() {
        lockedSince = nil
        reset()
    }

    mutating func observeLock(_ locked: Bool?, now: TimeInterval) {
        if locked == true {
            if lockedSince == nil { lockedSince = now }
        } else if locked == false {
            clearLockSession()
        }
        // A temporary unknown state must not rearm a completed lock session.
    }

    mutating func displayDidSleep() {
        displayAsleep = true
        sleepHandled = true
    }

    mutating func displayDidWake(now: TimeInterval) {
        displayAsleep = false
        sleepHandled = false
        if lockedSince != nil { lockedSince = now }
    }

    mutating func evaluate(now: TimeInterval, remote: RemoteState, locked: Bool?, asleep: Bool, idleSeconds: TimeInterval?) -> Bool {
        observeLock(locked, now: now)
        if asleep {
            displayDidSleep()
            return false
        }
        if displayAsleep { displayDidWake(now: now) }
        guard enabled, remote == .disconnected, locked == true, !blocked, !sleepHandled else { return false }
        guard let idleSeconds = idleSeconds, idleSeconds.isFinite, idleSeconds >= 0 else {
            // Require a full fresh interval after an unreadable input state.
            lockedSince = now
            return false
        }
        guard let lockedSince = lockedSince, now - lockedSince >= delay, idleSeconds >= delay else { return false }
        // Avoid duplicate requests until an actual sleep/wake transition rearms the timer.
        sleepHandled = true
        return true
    }
}

/// Follow one blackout through disconnect and local wake. Stop probing after unlock settles.
struct RecoveryChecks {
    private(set) var watching = false
    private var previousInput: UInt64?
    private var deadlines: [TimeInterval] = []

    mutating func beginBlackout() {
        watching = true
        previousInput = nil
        deadlines.removeAll()
    }

    mutating func schedule(now: TimeInterval) {
        guard watching else { return }
        deadlines = [now, now + 2, now + 8]
    }

    mutating func observeInput(_ count: UInt64, now: TimeInterval) -> Bool {
        defer { previousInput = count }
        guard let previousInput, previousInput != count else { return false }
        if deadlines.isEmpty { schedule(now: now) }
        return true
    }

    mutating func isDue(now: TimeInterval, locked: Bool?) -> Bool {
        guard watching else { return false }
        guard let first = deadlines.first else {
            if locked == false { watching = false }
            return false
        }
        return now >= first
    }

    mutating func shouldVerify(now: TimeInterval, locked: Bool?, remote: RemoteState, blackoutEnabled: Bool) -> Bool {
        guard !blackoutEnabled || remote == .disconnected else { return false }
        return isDue(now: now, locked: locked)
    }

    mutating func consume(now: TimeInterval) {
        deadlines.removeAll { $0 <= now }
    }
}
