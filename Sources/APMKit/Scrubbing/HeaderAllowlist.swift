import Foundation

/// docs/02 §6.1 SEC-02: header capture uses an **allowlist**, never a blocklist — default
/// allows only `Content-Type`, `Content-Length`, `Accept`, `User-Agent`; `Authorization`,
/// `Cookie`, and any custom header are never recorded.
///
/// Applied by `Scrubber` to the raw `req_headers`/`res_headers` JSON that
/// `NetworkCaptureDelegate` captures — `Scrubber` is the only place this filtering happens
/// (feat-003/feat-004 amendment, 2026-08-24).
enum HeaderAllowlist {
    static let defaultAllowedHeaders: Set<String> = ["Content-Type", "Content-Length", "Accept", "User-Agent"]

    static func filter(_ headers: [String: String], allowed: Set<String> = defaultAllowedHeaders) -> [String: String] {
        let lowercasedAllowed = Set(allowed.map { $0.lowercased() })
        return headers.filter { lowercasedAllowed.contains($0.key.lowercased()) }
    }
}
