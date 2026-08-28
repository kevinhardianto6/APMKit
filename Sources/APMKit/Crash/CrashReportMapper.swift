import Foundation

/// Maps one raw KSCrash report dictionary (`KSCrashReportDictionary.value`) to our `crash`
/// event schema (docs/01 §4.3). Pure and side-effect-free so it's directly unit-testable
/// against fixture dictionaries shaped like KSCrash's own `Example-Reports/*.json`, without
/// touching KSCrash itself.
///
/// `threads` and `binary_images` are re-serialized as JSON strings rather than decoded field
/// by field — `AttributeValue` only carries JSON scalars (same convention as breadcrumbs and
/// `req_headers` elsewhere), and the backend only needs raw addresses/symbols plus
/// `binary_images` + UUID for symbolication (MOB-17), not frame-level structure on our side.
enum CrashReportMapper {
    static func makeEvent(from report: [String: Any], seq: Int) -> Event? {
        guard let crash = report["crash"] as? [String: Any] else { return nil }
        let error = crash["error"] as? [String: Any] ?? [:]
        let errorType = error["type"] as? String ?? "unknown"
        let (name, reason) = extractNameReason(errorType: errorType, error: error)

        var attrs: [String: AttributeValue] = [
            "crash_type": .string(mapCrashType(errorType)),
            "name": .string(name),
            "reason": .string(reason),
            "is_fatal": .bool(isFatal(errorType: errorType, error: error))
        ]
        if let threads = crash["threads"] {
            attrs["threads"] = .string(jsonString(threads))
        }
        if let images = report["binary_images"] {
            attrs["binary_images"] = .string(jsonString(images))
        }
        if let breadcrumbsJSON = (report["user"] as? [String: Any])?["breadcrumbs"] as? String {
            attrs["breadcrumbs"] = .string(breadcrumbsJSON)
        }

        let stats = (report["system"] as? [String: Any])?["application_stats"] as? [String: Any] ?? [:]
        let activeSinceLaunch = (stats["active_time_since_launch"] as? Double) ?? 0
        let backgroundSinceLaunch = (stats["background_time_since_launch"] as? Double) ?? 0
        attrs["time_since_launch_ms"] = .int(Int((activeSinceLaunch + backgroundSinceLaunch) * 1000))

        let appState = (stats["application_in_foreground"] as? Bool).map { $0 ? "foreground" : "background" }

        return Event(
            type: "crash",
            timestamp: timestamp(from: report),
            seq: seq,
            attrs: attrs,
            ctx: EventContext(appState: appState)
        )
    }

    // MARK: - Field extraction

    /// docs/01 §4.3 `crash_type`: `signal` | `exception` | `anr` | `hang`. `anr` is
    /// Android-only (parity note docs/01 §4.3 header); iOS only ever produces the other three.
    private static func mapCrashType(_ errorType: String) -> String {
        switch errorType {
        case "signal", "mach", "deadlock", "termination": return "signal"
        case "hang": return "hang"
        default: return "exception" // nsexception, cpp_exception, user, profile, unknown
        }
    }

    /// Prefers KSCrash's own `is_fatal` when present (real reports carry it directly on
    /// `error`, confirmed against a live crash — see `CrashReportMapperTests` fixtures, which
    /// mirror the real shape, not the older nested-only assumption). Falls back to the
    /// resolved-hang heuristic only for report shapes that don't carry it.
    private static func isFatal(errorType: String, error: [String: Any]) -> Bool {
        if let explicit = error["is_fatal"] as? Bool { return explicit }
        guard errorType == "hang", let hang = error["hang"] as? [String: Any] else { return true }
        return (hang["hang_recovered"] as? Bool) != true
    }

    /// `reason` lives at the top level of `error` on a real KSCrash 2.6.0 report (confirmed
    /// against a live crash), not nested under `error.nsexception.reason` — a nested value is
    /// still preferred when present (older/other report shapes), with the top-level field as
    /// fallback so this doesn't silently drop the single most useful debugging string.
    private static func extractNameReason(errorType: String, error: [String: Any]) -> (name: String, reason: String) {
        let topLevelReason = error["reason"] as? String

        if let nsexception = error["nsexception"] as? [String: Any] {
            return (nsexception["name"] as? String ?? "NSException", nsexception["reason"] as? String ?? topLevelReason ?? "")
        }
        if let cppException = error["cpp_exception"] as? [String: Any] {
            return (cppException["name"] as? String ?? "CPPException", cppException["reason"] as? String ?? topLevelReason ?? "")
        }
        if let signal = error["signal"] as? [String: Any] {
            let signalName = signal["name"] as? String ?? "signal"
            let machExceptionName = (error["mach"] as? [String: Any])?["exception_name"] as? String
            return (signalName, topLevelReason ?? machExceptionName ?? "")
        }
        if errorType == "termination" {
            return ("termination", topLevelReason ?? "")
        }
        return (errorType, topLevelReason ?? "")
    }

    // MARK: - Formatting helpers

    /// KSCrash's report timestamp has no fractional seconds (e.g. `"1970-01-17T19:18:32Z"`),
    /// unlike our own `ISO8601Formatting` (`ts_client`) — try both rather than assume.
    private static let timestampFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func timestamp(from report: [String: Any]) -> Date {
        guard let raw = (report["report"] as? [String: Any])?["timestamp"] as? String else { return Date() }
        return timestampFormatterWithFractionalSeconds.date(from: raw) ?? timestampFormatter.date(from: raw) ?? Date()
    }

    private static func jsonString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else {
            return "null"
        }
        return String(data: data, encoding: .utf8) ?? "null"
    }
}
