import Foundation

/// Public entry point. Every method here is a boundary the host app calls across —
/// `CONSTITUTION.md` rule #1 applies from the first line of every one of them.
public enum APM {
    /// A `URLSession` pre-wired for network capture (docs/02 §3.1, MOB-01/02/03/10). Events
    /// are handed to `sink` — normally the scrubber in front of the disk queue (feat-004),
    /// never the disk queue directly (`CONSTITUTION.md`: Capture → Scrub → Disk → Sync).
    ///
    /// - Parameter excludedHosts: hosts never captured on this session — always include the
    ///   ingest host once it's configured (feat-005, MOB-10 anti-loop).
    /// - Parameter pinningDelegate: host app's certificate-pinning logic, if any. See
    ///   `NetworkCaptureForwardingDelegate`.
    /// - Returns: the session, plus the capture delegate in case the caller needs to attach
    ///   or replace `pinningDelegate` later (the session already retains it strongly).
    public static func instrumentedSession(
        configuration: URLSessionConfiguration = .default,
        sink: EventSink,
        sessionManager: SessionManager,
        excludedHosts: Set<String> = [],
        pinningDelegate: NetworkCaptureForwardingDelegate? = nil
    ) -> (session: URLSession, captureDelegate: NetworkCaptureDelegate) {
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
