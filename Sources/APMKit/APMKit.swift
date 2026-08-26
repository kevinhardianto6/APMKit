import Foundation

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
}
