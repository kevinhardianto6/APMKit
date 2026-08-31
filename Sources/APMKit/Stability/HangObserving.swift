import Foundation
#if canImport(KSCrashRecording)
import KSCrashRecording  // SPM: module name matches the "Recording" product
#else
import KSCrash  // CocoaPods: the KSCrash pod exposes one umbrella module, not per-subspec ones (feat-013)
#endif

/// This SDK's own vocabulary for a hang state change — decoupled from KSCrash's
/// `HangChangeType`, same reasoning as `CrashReportSource` wrapping KSCrash's report store:
/// `HangDetector` should be unit-testable without a real Watchdog monitor installed.
public enum HangChange {
    case started
    case updated
    case ended
}

/// Narrow interface over `KSCrash.shared.addHangObserver(_:)`, so `HangDetector` is
/// unit-testable without real signal/mach-level machinery — the same pattern `CrashReportSource`
/// and `CrashUserInfoStore` (feat-009) already use for the parts of KSCrash that touch real
/// OS-level monitoring.
public protocol HangObserving: AnyObject {
    /// Registers a callback for hang state changes. Returns an opaque token that must be
    /// retained to keep observing — releasing it unregisters. `nil` if hang observation isn't
    /// available (`KSCrashMonitorTypeWatchdog` not enabled via `CrashReporter.install()`).
    func addHangObserver(_ callback: @escaping (HangChange, _ startTimestampNs: UInt64, _ endTimestampNs: UInt64) -> Void) -> AnyObject?
}

/// Adapts KSCrash's real `addHangObserver` (via its `Hang` category on `KSCrash`) to
/// `HangObserving`.
public final class KSCrashHangObserving: HangObserving {
    public init() {}

    public func addHangObserver(_ callback: @escaping (HangChange, UInt64, UInt64) -> Void) -> AnyObject? {
        let token = KSCrash.shared.addHangObserver { change, start, end in
            let mapped: HangChange
            switch change {
            case .started: mapped = .started
            case .updated: mapped = .updated
            case .ended: mapped = .ended
            case .none: return
            @unknown default: return
            }
            callback(mapped, start, end)
        }
        return token as AnyObject?
    }
}
