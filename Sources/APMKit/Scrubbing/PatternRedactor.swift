import Foundation

/// Blanket PII pattern redaction — the SEC-05/05b "last layer" applied to every string value
/// that reaches the pipeline, regardless of which feature produced it. Purely string-in/
/// string-out so it's trivially reusable from any future feature (breadcrumbs, manual
/// `logError`, ...) without those features needing scrubbing awareness of their own.
enum PatternRedactor {
    private static let placeholder = "[redacted]"

    /// docs/02 §6.1 SEC-05 minimal pattern set. Order matters: JWT-like and email are
    /// checked before the generic digit-run pattern, since a JWT payload segment can itself
    /// contain a long digit run — checking the more specific pattern first keeps the whole
    /// token redacted as one unit rather than leaving token fragments exposed around a
    /// partially-redacted digit run.
    private static let patterns: [NSRegularExpression] = [
        // JWT-like: header segment is base64url of `{"..."}`, which always starts "eyJ".
        try! NSRegularExpression(pattern: #"eyJ[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]*"#),
        // Email.
        try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
        // Indonesian mobile: 08xxxxxxxxx or +628xxxxxxxxx (docs/02 §6.1 example numbers).
        try! NSRegularExpression(pattern: #"(?:\+62|0)8[0-9]{7,11}"#),
        // Any other run of 10+ digits — OTPs, account numbers, unlabeled long ids.
        try! NSRegularExpression(pattern: #"\d{10,}"#)
    ]

    static func redact(_ input: String) -> String {
        var output = input
        for pattern in patterns {
            let range = NSRange(output.startIndex..., in: output)
            output = pattern.stringByReplacingMatches(in: output, range: range, withTemplate: placeholder)
        }
        return output
    }
}
