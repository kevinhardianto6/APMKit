import Foundation

/// Maps one raw KSCrash report dictionary (`KSCrashReportDictionary.value`) to either our
/// `crash` event schema (docs/01 §4.3/§4.3.1/§4.3.2) or, for KSCrash's Termination-monitor
/// reports, our `termination` event schema (docs/01 §4.7, docs/02 MOB-15b). Pure and
/// side-effect-free so it's directly unit-testable against fixture dictionaries shaped like
/// KSCrash's own `Example-Reports/*.json`, without touching KSCrash itself.
///
/// `threads`/`binary_images` are reshaped (not just re-serialized) into docs/01 §4.3.1/§4.3.2's
/// exact wire shape — KSCrash's own raw field names/formats differ (decimal addresses instead
/// of hex strings, `image_addr`/`image_size`/`cpu_type` instead of `base_addr`/`size`/`arch`,
/// no `is_app` at all) — then re-serialized as one JSON string per array, since `AttributeValue`
/// only carries JSON scalars (same convention as breadcrumbs and `req_headers` elsewhere).
enum CrashReportMapper {
    /// `appBundlePath` defaults to this process's own bundle — real callers never override it;
    /// tests do, to exercise `is_app` without a real app bundle on the macOS host.
    static func makeEvent(from report: [String: Any], seq: Int, appBundlePath: String = Bundle.main.bundlePath) -> Event? {
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

        // `appOwnedNames` is derived from `binary_images` (the only place a full path exists —
        // KSCrash already reduces each frame's `object_name` to a basename before we ever see
        // it) and reused to compute every frame's `is_app`, so the two arrays must be built
        // together even though only one of them may end up in `attrs`.
        let rawImages = (report["binary_images"] as? [[String: Any]]) ?? []
        let (reshapedImages, appOwnedNames) = reshapeBinaryImages(rawImages, appBundlePath: appBundlePath)
        if report["binary_images"] != nil {
            attrs["binary_images"] = .string(jsonString(reshapedImages))
        }
        if let rawThreads = crash["threads"] as? [[String: Any]] {
            attrs["threads"] = .string(jsonString(reshapeThreads(rawThreads, appOwnedNames: appOwnedNames)))
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

    // MARK: - threads / binary_images reshaping (docs/01 §4.3.1/§4.3.2, MOB-17)

    /// Reshapes KSCrash's raw `binary_images` (absolute paths, decimal addresses, numeric
    /// `cpu_type`/`cpu_subtype`) into docs/01 §4.3.2's wire shape and computes `is_app`: `true`
    /// when the image's raw path lives inside this app's own bundle container — covering both
    /// the main executable and any app-embedded framework (e.g. `MerchantApp.app/Frameworks/…`)
    /// — `false` for anything outside it (`/System/Library/…`, `/usr/lib/…`). This can only
    /// happen here: the full path is available *only* on this top-level array, right now — by
    /// the time a frame references it, KSCrash has already reduced it to a basename, and
    /// deriving app-ownership downstream from a bare basename would be fragile (name collisions)
    /// and blind to app-owned frameworks (whose names don't match the app's own).
    ///
    /// Returns the reshaped array plus the set of basenames it classified as app-owned, so
    /// `reshapeThreads` can look up each frame's `object_name` (already a basename) against it.
    private static func reshapeBinaryImages(
        _ rawImages: [[String: Any]],
        appBundlePath: String
    ) -> (json: [[String: Any]], appOwnedNames: Set<String>) {
        var appOwnedNames: Set<String> = []
        let reshaped: [[String: Any]] = rawImages.map { image in
            let fullPath = image["name"] as? String ?? ""
            let name = (fullPath as NSString).lastPathComponent
            // An empty `appBundlePath` must never mean "everything matches" — `"x".hasPrefix("")`
            // is `true` in Swift, which would misclassify every system binary as app-owned.
            let isApp = !appBundlePath.isEmpty && fullPath.hasPrefix(appBundlePath)
            if isApp { appOwnedNames.insert(name) }
            return [
                "name": name,
                "uuid": image["uuid"] ?? NSNull(),
                "base_addr": hexAddress(image["image_addr"]),
                "size": image["image_size"] ?? 0,
                "arch": archString(cpuType: image["cpu_type"], cpuSubType: image["cpu_subtype"]),
                "is_app": isApp
            ]
        }
        return (reshaped, appOwnedNames)
    }

    /// Reshapes KSCrash's raw `threads` (each a flat dict with `index`/`crashed`/`name`/
    /// `dispatch_queue` plus a nested `backtrace.contents` array of frames) into docs/01
    /// §4.3.1's shape: a flat `frames` array per thread, hex address strings, `is_app` looked
    /// up from `appOwnedNames`, and `symbol_name`/`file`/`line` — the last two always `null`
    /// here; only the backend fills them in, post-symbolication (BE-11).
    private static func reshapeThreads(_ rawThreads: [[String: Any]], appOwnedNames: Set<String>) -> [[String: Any]] {
        rawThreads.map { thread in
            let rawFrames = (thread["backtrace"] as? [String: Any])?["contents"] as? [[String: Any]] ?? []
            let frames: [[String: Any]] = rawFrames.map { frame in
                let objectName = frame["object_name"] as? String ?? ""
                return [
                    "index": frame["index"] ?? 0,
                    "object_name": objectName,
                    "object_addr": hexAddress(frame["object_addr"]),
                    "instruction_addr": hexAddress(frame["instruction_addr"]),
                    "is_app": appOwnedNames.contains(objectName),
                    "symbol_name": frame["symbol_name"] ?? NSNull(),
                    "file": NSNull(),
                    "line": NSNull()
                ]
            }
            return [
                "index": thread["index"] ?? 0,
                "crashed": thread["crashed"] ?? false,
                // KSCrash only sets a pthread `name` when one was actually assigned; every
                // thread has a `dispatch_queue` label (e.g. "com.apple.main-thread" for main),
                // which is the fallback docs/01 §4.3.1's own example is built from.
                "name": ((thread["name"] as? String) ?? (thread["dispatch_queue"] as? String)) as Any? ?? NSNull(),
                "frames": frames
            ]
        }
    }

    /// KSCrash gives raw addresses as plain decimal numbers (`Int`/`Double`, depending on how
    /// the raw dict was bridged) — docs/01 §4.3.1/§4.3.2's own example is a lowercase `0x…`
    /// hex string, so this normalizes either numeric shape to that.
    private static func hexAddress(_ rawAddress: Any?) -> String {
        if let intValue = rawAddress as? Int {
            return String(format: "0x%llx", intValue)
        }
        if let doubleValue = rawAddress as? Double {
            return String(format: "0x%llx", Int64(doubleValue))
        }
        return "0x0"
    }

    /// Mach-O `cpu_type_t`/`cpu_subtype_t` (`<mach/machine.h>`) → docs/01 §4.3.2's `arch`
    /// string. Hardcoded rather than imported from Darwin (the raw macros are bitwise
    /// expressions the Swift Clang importer doesn't reliably expose) or pulled from KSCrash's
    /// own private `kscpu_archForCPU` (would need a new module dependency — `RecordingCore` —
    /// for six stable, decades-old constants). Covers every arch this SDK's deployment target
    /// (iOS 15+ device and Simulator) can actually report; anything else falls back to a
    /// labeled raw value rather than guessing.
    private static func archString(cpuType: Any?, cpuSubType: Any?) -> String {
        let cpuType = (cpuType as? Int) ?? 0
        let cpuSubType = (cpuSubType as? Int) ?? 0
        let cpuTypeARM64 = 0x0100000C
        let cpuTypeX86_64 = 0x01000007
        let cpuSubtypeARM64E = 2
        switch cpuType {
        case cpuTypeARM64:
            return cpuSubType == cpuSubtypeARM64E ? "arm64e" : "arm64"
        case cpuTypeX86_64:
            return "x86_64"
        default:
            return "unknown(\(cpuType),\(cpuSubType))"
        }
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
