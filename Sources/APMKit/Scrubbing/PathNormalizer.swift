import Foundation

/// docs/02 §6.1 SEC-03b: replaces path segments that look like an identifier (UUID, or a
/// long run of digits) with `{id}` — `/user/628123456789/profile` → `/user/{id}/profile`.
/// Keeps PII out of the path and improves backend fingerprinting quality (docs/01 §6): an
/// unnormalized path fragments one real issue into thousands of unique ones.
enum PathNormalizer {
    private static let uuidPattern = try! NSRegularExpression(
        pattern: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
    )
    /// 5+ digits is a judgment call (docs/02 says only "angka panjang" / "long numbers"
    /// without a threshold) — long enough to not catch small counts/indices like `/v2/`,
    /// short enough to catch realistic ids. `PatternRedactor`'s separate ≥10-digit rule still
    /// runs afterward as a second layer regardless of this threshold.
    private static let longDigitRunPattern = try! NSRegularExpression(pattern: #"\d{5,}"#)

    static func normalize(_ path: String) -> String {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        let normalized = segments.map { segment -> String in
            let value = String(segment)
            guard !value.isEmpty else { return value }
            return (isUUID(value) || containsLongDigitRun(value)) ? "{id}" : value
        }
        return normalized.joined(separator: "/")
    }

    private static func isUUID(_ segment: String) -> Bool {
        let range = NSRange(segment.startIndex..., in: segment)
        return uuidPattern.firstMatch(in: segment, range: range) != nil
    }

    private static func containsLongDigitRun(_ segment: String) -> Bool {
        let range = NSRange(segment.startIndex..., in: segment)
        return longDigitRunPattern.firstMatch(in: segment, range: range) != nil
    }
}
