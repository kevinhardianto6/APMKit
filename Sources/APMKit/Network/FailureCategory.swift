import Foundation

/// docs/01 §5 — identical values on iOS & Android; used for grouping/filtering in the
/// dashboard, so the raw strings are the wire contract, not an implementation detail.
public enum FailureCategory: String, Codable, Equatable {
    case sslCertificate = "ssl_certificate"
    case sslPinningRejected = "ssl_pinning_rejected"
    case tlsHandshake = "tls_handshake"
    case timeout
    case dns
    case connectivity
    case cancelled
    case httpError = "http_error"
    case unknown
}

/// docs/01 §4.2 `tls_phase_reached` — how far the TLS handshake got before the request failed.
public enum TLSPhase: String, Codable, Equatable {
    case none, started, completed
}
