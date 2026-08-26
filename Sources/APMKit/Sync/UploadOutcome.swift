import Foundation

/// docs/01 §7 — the exact response-code contract for `POST /v1/ingest`. Each case is the
/// SDK's required action, not just the raw status code, so `SyncEngine` never has to
/// re-derive "what does a 413 mean" from a bare `Int`.
public enum UploadOutcome: Equatable {
    /// 202 — delete the batch from disk.
    case accepted
    /// 400 — payload malformed / unknown schema. Drop the batch; never retry it.
    case rejected
    /// 401/403 — invalid key. Pause sending for 24h; keep data on disk.
    case unauthorized
    /// 413 — payload too large. Split the batch in half and retry.
    case payloadTooLarge
    /// 429 — rate limited. Honor `Retry-After` if the server sent one.
    case rateLimited(retryAfterSeconds: TimeInterval?)
    /// 5xx — server error. Exponential backoff; keep data on disk.
    case serverError
    /// No response at all (offline, DNS failure, timeout, ...). Not explicitly in the §7
    /// table (which only covers responses the server actually sent), but the SDK must do
    /// something reasonable here too: exponential backoff, keep data on disk — write local
    /// first means offline is an expected, unremarkable state, not an error to surface.
    case transportFailure
}
