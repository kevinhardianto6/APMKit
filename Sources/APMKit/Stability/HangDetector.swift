import Foundation

/// Main-thread hang detection (docs/02 §3.6, MOB-18: "hang main thread > 2 detik (iOS)").
///
/// **Wraps KSCrash's own `Watchdog` monitor rather than hand-rolling a timer** — the same
/// "wrap a mature library, don't hand-roll" reasoning `CONSTITUTION.md`/docs/00 §11 decision 4
/// already applies to crash reporting generally applies here. KSCrash's Watchdog monitor is
/// exactly "a timer watching the main run loop" done safely: a `CFRunLoopObserver` on the main
/// run loop plus a dedicated high-priority watchdog *thread* running its own run loop with a
/// repeating timer — the main thread is only ever touched with a relaxed-ordering atomic
/// timestamp write, never blocked or locked. This SDK does not add any of that machinery
/// itself; hand-rolling a second, competing hang detector next to KSCrash's would be the risk
/// the user explicitly asked to avoid, not a safer alternative to it.
///
/// This is deliberately **separate** from feat-009's `CrashReportProcessor` next-launch
/// pipeline: that pipeline handles *fatal* watchdog terminations (the OS actually kills the
/// process, `0x8badf00d`) read from disk on the next launch — `CrashReportMapper` already
/// handles `crash_type: hang` there defensively. `HangDetector` handles the *other* case MOB-18
/// actually asks for: a hang that resolves on its own (the main thread becomes responsive
/// again), reported live, in the same process, through the normal `EventSink` pipeline — not
/// written to KSCrash's own report store at all (`kscm_watchdog_setReportsHangs` stays at its
/// default `false`; this SDK doesn't need KSCrash to separately persist what it just captured
/// live).
///
/// The `KSHangChangeTypeStarted`/`Updated` callbacks are intentionally ignored — only `.ended`
/// (final, resolved duration known) produces an event, filtered to `threshold` (MOB-18: 2s).
/// KSCrash's own internal detection threshold (250ms, matching Apple's own hang-duration
/// guidance) is unrelated and not configurable from here; it only controls when the observer
/// starts getting `.started`/`.updated` callbacks, not what this SDK reports.
public final class HangDetector {
    public static let shared = HangDetector()

    private let observing: HangObserving
    private let threshold: TimeInterval
    private var token: AnyObject?

    public init(observing: HangObserving = KSCrashHangObserving(), threshold: TimeInterval = 2.0) {
        self.observing = observing
        self.threshold = threshold
    }

    /// Starts observing. Requires `KSCrashMonitorTypeWatchdog` to already be enabled
    /// (`CrashReporter.install()`) — if it isn't, `addHangObserver` returns `nil` and this
    /// does nothing (`CONSTITUTION.md` rule #1: a missing precondition fails silently, never
    /// throws into the host). Call once; calling again replaces the previous observation.
    public func start(sink: EventSink, sessionManager: SessionManager) {
        token = observing.addHangObserver { [weak self] change, startNs, endNs in
            guard let self, change == .ended else { return }
            let durationSeconds = Double(endNs - startNs) / 1_000_000_000
            guard durationSeconds >= self.threshold else { return }

            sink.receive(Event(
                type: "crash",
                seq: sessionManager.nextSequenceNumber(),
                attrs: [
                    "crash_type": .string("hang"),
                    "name": .string("MainThreadHang"),
                    "reason": .string("main thread blocked for \(Int(durationSeconds * 1000))ms"),
                    "is_fatal": .bool(false)
                ]
            ))
        }
    }

    /// Stops observing — releases the token, which unregisters with KSCrash.
    public func stop() {
        token = nil
    }
}
