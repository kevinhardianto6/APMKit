import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Cold-start metric (docs/01 §4.6 `lifecycle`, docs/02 §3.6 MOB-19): "waktu sampai frame
/// pertama" — time from process start to first frame.
///
/// **Host-invoked by design, not automatic — same reasoning as MOB-12's screen tracking**
/// (`ScreenTracking.swift`, docs/02 §3.4). The only automatic way to know "first frame drawn"
/// is swizzling `CALayer`/`UIViewController` display methods, which `CONSTITUTION.md` and
/// MOB-12's own precedent already reject for this SDK: it risks crashing the host app and
/// collides with other SDKs doing the same swizzle. So this exposes a primitive,
/// `recordFirstFrame(sink:sessionManager:)`, for the host to call once from wherever *they*
/// consider "first frame" — typically a `CATransaction` completion block set up around the
/// initial screen's first layout, or that screen's `viewDidAppear`. This is a real, non-zero-
/// effort integration step and should be documented as prominently as MOB-12's is (MOB-25).
///
/// Process start time is read via `sysctl`/`kinfo_proc.p_starttime` — the same portable
/// (Darwin, not iOS-only) mechanism `DeviceIntegrityDetector.isDebuggerAttached` already uses,
/// so unlike MOB-12's own true-branch, this is genuinely exercised by `swift test` on the
/// macOS host, not just proven correct by construction.
public final class ColdStartTracker {
    public static let shared = ColdStartTracker()

    private let lock = NSLock()
    private var recorded = false
    private let processStartTime: Date?

    public init(processStartTime: Date? = ColdStartTracker.currentProcessStartTime()) {
        self.processStartTime = processStartTime
    }

    /// Idempotent — only the first call after this tracker's creation does anything. A host
    /// app that calls this from more than one place (e.g. both a `CATransaction` completion
    /// and a fallback timeout) can't accidentally emit two cold-start events for one launch.
    public func recordFirstFrame(sink: EventSink, sessionManager: SessionManager, now: Date = Date()) {
        lock.lock()
        guard !recorded, let processStartTime else {
            lock.unlock()
            return
        }
        recorded = true
        lock.unlock()

        let durationMs = Int(now.timeIntervalSince(processStartTime) * 1000)
        // Defensive (CONSTITUTION.md rule #1): a clock adjustment or bad sysctl read must
        // never produce a negative/garbage metric that pollutes cold-start dashboards.
        guard durationMs >= 0 else { return }

        sink.receive(Event(
            type: "lifecycle",
            seq: sessionManager.nextSequenceNumber(),
            attrs: ["state": "cold_start", "duration_ms": .int(durationMs)]
        ))
    }

    #if canImport(Darwin)
    public static func currentProcessStartTime() -> Date? {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        let seconds = TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
        return Date(timeIntervalSince1970: seconds)
    }
    #else
    public static func currentProcessStartTime() -> Date? { nil }
    #endif
}
