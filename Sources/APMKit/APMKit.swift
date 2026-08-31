import Foundation
#if canImport(KSCrashRecording)
import KSCrashRecording  // SPM: module name matches the "Recording" product
#else
import KSCrash  // CocoaPods: the KSCrash pod exposes one umbrella module, not per-subspec ones (feat-013)
#endif

/// Public entry point. Every method here is a boundary the host app calls across —
/// `CONSTITUTION.md` rule #1 applies from the first line of every one of them.
public enum APM {
    /// A `URLSession` pre-wired for network capture (docs/02 §3.1, MOB-01/02/03/10). Events
    /// are handed to `sink` — normally the scrubber in front of the disk queue (feat-004),
    /// never the disk queue directly (`CONSTITUTION.md`: Capture → Scrub → Disk → Sync).
    ///
    /// - Parameter ingestEndpoint: APM Kit's own upload destination. **Required, not
    ///   optional** — its host is automatically added to the exclusion set (MOB-10/MOB-09
    ///   anti-loop), so a host app cannot construct an instrumented session that ends up
    ///   capturing its own upload traffic. This is deliberate: an anti-loop guarantee that
    ///   depends on the integrator remembering a separate step is not a guarantee. Pass the
    ///   same `IngestEndpoint` used to build the `IngestClient` for sync (feat-005) — that's
    ///   what keeps the two in sync with each other.
    /// - Parameter additionalExcludedHosts: any other hosts to exclude beyond the ingest host
    ///   (e.g. a symbol-upload endpoint, once one exists).
    /// - Parameter pinningDelegate: host app's certificate-pinning logic, if any. See
    ///   `NetworkCaptureForwardingDelegate`.
    /// - Returns: the session, plus the capture delegate in case the caller needs to attach
    ///   or replace `pinningDelegate` later (the session already retains it strongly).
    public static func instrumentedSession(
        configuration: URLSessionConfiguration = .default,
        sink: EventSink,
        sessionManager: SessionManager,
        ingestEndpoint: IngestEndpoint,
        additionalExcludedHosts: Set<String> = [],
        pinningDelegate: NetworkCaptureForwardingDelegate? = nil
    ) -> (session: URLSession, captureDelegate: NetworkCaptureDelegate) {
        var excludedHosts = additionalExcludedHosts
        if let ingestHost = ingestEndpoint.url.host {
            excludedHosts.insert(ingestHost)
        }

        let captureDelegate = NetworkCaptureDelegate(
            sink: sink,
            sessionManager: sessionManager,
            excludedHosts: excludedHosts
        )
        captureDelegate.forwardingDelegate = pinningDelegate
        let session = URLSession(configuration: configuration, delegate: captureDelegate, delegateQueue: nil)
        return (session, captureDelegate)
    }

    /// Sets `envelope.user_id` (docs/01 §2.1, MOB-28, SEC-06). Accepts **any** free-form
    /// string — a phone number, email, internal id, anything. The SDK sends it **raw**, never
    /// hashes or validates it; hashing to the opaque `user_ref` is the backend's job at
    /// ingestion. If never called, the SDK falls back to a stable random id persisted per
    /// install (`UserIdentity.currentUserId()`, read by `EnvelopeFactory`).
    public static func setUser(id: String) {
        UserIdentity.setUser(id: id)
    }

    /// Reports a handled error (docs/01 §4.4, docs/02 §3.4 MOB-11). See `ManualReporter` —
    /// takes an explicit `sink`/`sessionManager` for now, matching `instrumentedSession()`'s
    /// dependency style; there is no composition root yet to hold that state for a
    /// zero-argument call (feat-006/010 territory once one exists).
    public static func logError(
        _ error: Error,
        context: [String: String] = [:],
        sink: EventSink,
        sessionManager: SessionManager
    ) {
        ManualReporter(sink: sink, sessionManager: sessionManager).logError(error, context: context)
    }

    /// Records a breadcrumb (docs/01 §4.5, docs/02 §3.4 MOB-11/12/13) — a small chronological
    /// trail of what happened before an error, not an event of its own. Appends to the
    /// shared ring buffer (last 100); `ManualReporter.logError` attaches a snapshot to the
    /// resulting `error` event. `message` is developer-supplied free text and gets scrubbed
    /// there, along with everything else — this call itself does no PII handling.
    public static func breadcrumb(_ message: String, category: BreadcrumbCategory, level: BreadcrumbLevel = .info) {
        BreadcrumbRingBuffer.shared.add(Breadcrumb(category: category, message: message, level: level))
    }

    /// Records the cold-start metric (docs/01 §4.6, MOB-19) — call once, from wherever the
    /// host app considers "first frame drawn" (see `ColdStartTracker`'s doc comment for why
    /// this is host-invoked rather than automatic, same reasoning as MOB-12's screen
    /// tracking). Idempotent: a second call this process does nothing.
    public static func recordFirstFrame(sink: EventSink, sessionManager: SessionManager) {
        ColdStartTracker.shared.recordFirstFrame(sink: sink, sessionManager: sessionManager)
    }

    /// Installs crash monitoring (docs/02 §3.5, MOB-15/16/17) **and** drains whatever
    /// KSCrash captured during the *previous* run through `sink`/`sessionManager` — same
    /// explicit-dependency style as `logError`/`instrumentedSession`. Deliberately one call,
    /// not two: a `processPendingCrashReports` the host has to remember to call separately is
    /// the same failure shape as feat-005's anti-loop problem (MOB-09/10) — a safety property
    /// that depends on the integrator remembering a second step isn't a guarantee. Draining is
    /// the point of this feature (MOB-16: "sent on next launch"); folding it into the one call
    /// every integration needs anyway (`install`) makes forgetting it structurally impossible.
    ///
    /// Call once, as early as possible during app launch. The KSCrash install itself is
    /// synchronous (KSCrash's own rule: fast, no heavy work on the launch path); draining is
    /// dispatched to a background queue so a launch-time call from the main thread never
    /// becomes blocking I/O (docs/02 §5 perf budget). Note this is the same pre-existing
    /// caveat `SessionManager` already documents for every other capture path (network capture
    /// touches it from URLSession's delegate queue, manual `logError`/`breadcrumb` from
    /// whatever thread the host calls them on) — this dispatch doesn't introduce a new
    /// thread-safety requirement, it's subject to the same one every other feature already is.
    ///
    /// - Parameter installPath: see `CrashReporter.install(installPath:)` — production callers
    ///   should never pass this; it exists for `IOSCrashHarnessTests`.
    @discardableResult
    public static func installCrashReporting(sink: EventSink, sessionManager: SessionManager, installPath: String? = nil) -> Bool {
        let installed = CrashReporter.shared.install(installPath: installPath)
        guard installed else { return false }
        crashProcessingQueue.async {
            processPendingCrashReports(sink: sink, sessionManager: sessionManager)
        }
        return true
    }

    private static let crashProcessingQueue = DispatchQueue(label: "kit.apm.crash-processing")

    /// Reads every crash report KSCrash captured during a previous run, converts each to a
    /// `crash` event (docs/01 §4.3) through `sink`/`sessionManager`, and clears it from
    /// KSCrash's own raw store (`CrashReportProcessor`). Exposed separately for tests and for
    /// callers who need explicit control over timing; `installCrashReporting` already calls
    /// this for the normal path, so most integrations never need to call it directly.
    public static func processPendingCrashReports(sink: EventSink, sessionManager: SessionManager) {
        guard let store = KSCrash.shared.reportStore else { return }
        CrashReportProcessor(
            source: KSCrashReportSource(store: store),
            sink: sink,
            sessionManager: sessionManager
        ).processPendingReports()
    }

    /// Starts main-thread hang detection (docs/02 §3.6, MOB-18). Requires
    /// `installCrashReporting` to have been called first (it's what enables KSCrash's
    /// `Watchdog` monitor) — if it hasn't, this silently does nothing, per
    /// `CONSTITUTION.md` rule #1. See `HangDetector`'s doc comment for why this wraps
    /// KSCrash's own hang monitor rather than a hand-rolled timer.
    public static func startHangDetection(sink: EventSink, sessionManager: SessionManager) {
        HangDetector.shared.start(sink: sink, sessionManager: sessionManager)
    }

    /// Fetches `GET /v1/config` (docs/01 §9, MOB-20) and applies the result to `configStore` —
    /// which is what `KillSwitch` and `SyncEngine`'s `isEnabled` closure read from (MOB-21).
    /// Call once at startup, after constructing `configStore`, which is itself already usable
    /// synchronously before this call returns (seeded from cache/`.safeDefault` at its own
    /// `init`) — this call only ever *improves* on that, never blocks anything on it.
    ///
    /// - Parameter session: must never be `APM.instrumentedSession()` — same MOB-09 anti-loop
    ///   rule as `IngestClient`. The default constructs a bare session with no delegate.
    public static func fetchRemoteConfig(
        endpoint: IngestEndpoint,
        configStore: RemoteConfigStore,
        session: URLSession = URLSession(configuration: .default)
    ) {
        RemoteConfigFetcher(endpoint: endpoint, session: session).fetch { config in
            configStore.apply(config)
        }
    }
}
