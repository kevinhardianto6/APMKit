import Foundation

/// Maps one raw KSCrash report dictionary (`KSCrashReportDictionary.value`) to either our
/// `crash` event schema (docs/01 §4.3) or, for KSCrash's Termination-monitor reports, our
/// `termination` event schema (docs/01 §4.7, docs/02 MOB-15b). Pure and side-effect-free so
/// it's directly unit-testable against fixture dictionaries shaped like KSCrash's own
/// `Example-Reports/*.json`, without touching KSCrash itself.
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

        if errorType == "termination" {
            return makeTerminationEvent(from: report, error: error, seq: seq)
        }

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
        attrs["time_since_launch_ms"] = .int(timeSinceLaunchMs(from: report))

        return Event(
            type: "crash",
            timestamp: timestamp(from: report),
            seq: seq,
            attrs: attrs,
            ctx: EventContext(appState: appState(from: report))
        )
    }

    // MARK: - termination (docs/01 §4.7, docs/02 MOB-15b)

    /// KSCrash's Termination monitor injects a synthetic report — complete with a fake
    /// `signal: SIGKILL` block "for backward compatibility" — for OS-level kills that could
    /// never be caught live: an Xcode Stop-button kill, the user swiping the app away, a
    /// rebuild, or the system reclaiming memory under pressure. It's not a crash (no stack,
    /// not caused by or catchable by app code) — 2026-09-01 real-run finding, spec decision in
    /// docs/01 §4.7 / docs/02 MOB-15b, full reasoning in `CONSTITUTION.md`.
    ///
    /// Only the five resource-heuristic causes KSCrash can actually back with evidence (the
    /// specific critical resource state was observed in the last snapshot before death) become
    /// a `termination` event. `unexplained` — and anything else unrecognized — is dropped: the
    /// OS gives no signal after SIGKILL, so it's indistinguishable from an ordinary dev/user
    /// termination and carries no diagnostic value (§4.7's explicit "why `unexplained` is
    /// dropped" note).
    private static let terminationReasonEnum: Set<String> = [
        "memory_limit", "memory_pressure", "cpu", "thermal", "low_battery"
    ]

    private static func makeTerminationEvent(from report: [String: Any], error: [String: Any], seq: Int) -> Event? {
        guard let reason = error["termination_reason"] as? String, terminationReasonEnum.contains(reason) else {
            return nil
        }

        return Event(
            type: "termination",
            timestamp: timestamp(from: report),
            seq: seq,
            attrs: [
                "termination_reason": .string(reason),
                "time_since_launch_ms": .int(timeSinceLaunchMs(from: report))
            ],
            ctx: EventContext(appState: appState(from: report))
        )
    }

    // MARK: - Field extraction

    private static func timeSinceLaunchMs(from report: [String: Any]) -> Int {
        let stats = (report["system"] as? [String: Any])?["application_stats"] as? [String: Any] ?? [:]
        let activeSinceLaunch = (stats["active_time_since_launch"] as? Double) ?? 0
        let backgroundSinceLaunch = (stats["background_time_since_launch"] as? Double) ?? 0
        return Int((activeSinceLaunch + backgroundSinceLaunch) * 1000)
    }

    private static func appState(from report: [String: Any]) -> String? {
        let stats = (report["system"] as? [String: Any])?["application_stats"] as? [String: Any] ?? [:]
        return (stats["application_in_foreground"] as? Bool).map { $0 ? "foreground" : "background" }
    }

    /// docs/01 §4.3 `crash_type`: `signal` | `exception` | `anr` | `hang`. `anr` is
    /// Android-only (parity note docs/01 §4.3 header); iOS only ever produces the other three.
    /// `errorType == "termination"` never reaches here — `makeEvent` routes it to
    /// `makeTerminationEvent` instead (docs/01 §4.7, a distinct event type).
    private static func mapCrashType(_ errorType: String) -> String {
        switch errorType {
        case "signal", "mach", "deadlock": return "signal"
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
