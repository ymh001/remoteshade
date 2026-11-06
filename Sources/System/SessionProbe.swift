import AppKit
import CoreGraphics
import IOKit
import IOKit.pwr_mgt
import Darwin

enum RemoteState: String { case connected = "远控已连接", disconnected = "未发现 Apple 远控连接", unknown = "远控检测不可用" }

struct SessionProbe {
    static func remoteState() -> RemoteState {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dictionary = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return .unknown }
        for (pid, assertions) in dictionary {
            var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
            guard proc_pidpath(pid.int32Value, &buffer, UInt32(buffer.count)) > 0 else { continue }
            let path = String(cString: buffer)
            guard path == "/System/Library/CoreServices/RemoteManagement/screensharingd.bundle/Contents/MacOS/screensharingd" || path == "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/MacOS/ARDAgent" else { continue }
            if assertions.contains(where: {
                ($0[kIOPMAssertionNameKey] as? String) == "Remote user is connected" &&
                ($0[kIOPMAssertionLevelKey] as? NSNumber)?.intValue == 255
            }) { return .connected }
        }
        return .disconnected
    }

    static func locked(lastNotification: Bool? = nil) -> Bool? {
        guard let values = CGSessionCopyCurrentDictionary() as? [String: Any],
              values[kCGSessionOnConsoleKey as String] as? Bool == true else { return nil }
        // This key is undocumented. Distributed notifications complement polling.
        return values["CGSSessionScreenIsLocked"] as? Bool ?? lastNotification ?? false
    }

    /// IOHIDSystem counts idle time across local input, including secure password entry.
    /// Read only elapsed time, never keyboard events or their contents.
    static func localIdleSeconds() -> TimeInterval? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else { return nil }
        let seconds = value.doubleValue / 1_000_000_000
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    static func localInputCount() -> UInt64 {
        // Counters only. No event tap or key contents are needed at the lock screen.
        [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown].reduce(UInt64(0)) { count, type in
            count &+ UInt64(CGEventSource.counterForEventType(.hidSystemState, eventType: type))
        }
    }

    static func displaysAsleep() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).allSatisfy { CGDisplayIsAsleep($0) != 0 }
    }
}
