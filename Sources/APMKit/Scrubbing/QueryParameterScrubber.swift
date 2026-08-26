import Foundation

/// docs/02 §6.1 SEC-03: query parameter **values** are redacted; only parameter names are
/// kept. An app-configurable allowlist can exempt specific parameter names from redaction
/// (e.g. non-sensitive pagination params like `page`).
///
/// Applied by `Scrubber` to the raw `?query=string` suffix that `NetworkCaptureDelegate`
/// appends to the `path` attribute — `Scrubber` is the only place this redaction happens
/// (feat-003/feat-004 amendment, 2026-08-24).
enum QueryParameterScrubber {
    private static let placeholder = "[redacted]"

    static func scrub(queryString: String, valueAllowlist: Set<String> = []) -> String {
        guard !queryString.isEmpty else { return queryString }
        return queryString
            .split(separator: "&", omittingEmptySubsequences: false)
            .map { pair -> String in
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let name = parts.first else { return String(pair) }
                return valueAllowlist.contains(String(name)) ? String(pair) : "\(name)=\(placeholder)"
            }
            .joined(separator: "&")
    }
}
