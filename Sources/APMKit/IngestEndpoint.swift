import Foundation

/// Identifies APM Kit's own ingestion endpoint — the single source of truth that both
/// `APM.instrumentedSession()` (to exclude it from capture, MOB-10 anti-loop) and
/// `IngestClient` (to actually upload to it) read from.
///
/// This exists specifically so the anti-loop guarantee is automatic rather than a manual
/// integration step a host app can forget: `instrumentedSession()` requires one of these and
/// computes the exclusion internally, instead of asking the caller to separately remember to
/// list the ingest host in `excludedHosts`. Two different features (feat-003's capture,
/// feat-005's sync) share one type instead of each holding their own copy of "where uploads
/// go" that could silently drift out of sync with each other.
public struct IngestEndpoint: Equatable {
    public var url: URL
    public var appKey: String

    public init(url: URL, appKey: String) {
        self.url = url
        self.appKey = appKey
    }

    /// `GET /v1/config` (docs/01 §9) — a sibling of `url` (`.../v1/ingest`) under the same
    /// host, so remote-config fetches automatically share MOB-10's anti-loop exclusion with
    /// ingest uploads (`APM.instrumentedSession()` excludes by host, not by path).
    public var configURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("config")
    }
}
