import Foundation

/// Maps a transport-level failure to `failure_category` (docs/01 §5). Pure and
/// networking-free by design, so every category is directly unit-testable with a synthetic
/// `NSError` instead of needing to reproduce the real network condition.
enum FailureCategoryMapper {
    /// - Parameter pinningRejected: set by `NetworkCaptureDelegate` when it observed a
    ///   server-trust challenge get rejected by the host app's own pinning logic. Per docs/01
    ///   §5's implementation note, a custom pinning rejection surfaces as a plain
    ///   `NSURLErrorCancelled` — indistinguishable from a normal `task.cancel()` by error code
    ///   alone, which is why this has to be threaded through as separate state rather than
    ///   derived from `error`.
    static func map(error: NSError, pinningRejected: Bool) -> FailureCategory {
        guard error.domain == NSURLErrorDomain else { return .unknown }
        if pinningRejected { return .sslPinningRejected }

        switch error.code {
        case NSURLErrorCancelled:
            return .cancelled
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return .dns
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed,
             NSURLErrorCannotConnectToHost,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive:
            return .connectivity
        case NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return .sslCertificate
        case NSURLErrorSecureConnectionFailed:
            return .tlsHandshake
        default:
            return .unknown
        }
    }

    /// docs/01 §4.2 `tls_phase_reached`, derived from the transaction's TLS handshake dates.
    static func tlsPhaseReached(secureConnectionStart: Date?, secureConnectionEnd: Date?) -> TLSPhase {
        if secureConnectionStart != nil && secureConnectionEnd != nil { return .completed }
        if secureConnectionStart != nil { return .started }
        return .none
    }
}
