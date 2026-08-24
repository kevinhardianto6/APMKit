import Foundation

/// Shared formatter for `ts_client` (docs/01 §3) — e.g. `"2026-07-24T09:12:33.412Z"`.
/// `ISO8601DateFormatter` is not thread-safe for mutation, but read-only use of a shared
/// instance (as done here) is safe per Apple's documentation.
enum ISO8601Formatting {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
