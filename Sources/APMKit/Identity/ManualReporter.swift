import Foundation

/// Developer-facing manual reporting API (docs/01 §4.4 `error`, docs/02 §3.4 MOB-11).
/// Mirrors `NetworkCaptureDelegate`'s explicit-dependency style (holds `sink` +
/// `sessionManager` rather than reaching for ambient/global state) — consistent with the rest
/// of the SDK at this stage, where no composition root exists yet to hold shared state for a
/// static `APM.logError(_:)` to reach into.
///
/// Events handed to `sink` are raw/unscrubbed by design — same layering as network capture
/// (`CONSTITUTION.md`: Capture → **Scrub** → Disk → Sync). `custom.*` context values pass
/// through the same `Scrubber` every other event does; this type has no PII-handling logic of
/// its own and must not grow any (SEC-05b already covers manual-API data generically).
public final class ManualReporter {
    private let sink: EventSink
    private let sessionManager: SessionManager

    /// docs/01 §4.4: "Maks 20 key, masing-masing ≤ 256 karakter."
    private static let maxCustomKeys = 20
    private static let maxCustomValueLength = 256

    public init(sink: EventSink, sessionManager: SessionManager) {
        self.sink = sink
        self.sessionManager = sessionManager
    }

    /// Reports a handled error (docs/01 §4.4: `handled` is always `true` for this path —
    /// unhandled crashes are feat-009's domain, wrapping KSCrash).
    public func logError(_ error: Error, context: [String: String] = [:]) {
        let nsError = error as NSError

        var attrs: [String: AttributeValue] = [
            "name": .string(String(describing: type(of: error))),
            "message": .string(nsError.localizedDescription),
            "domain": .string(nsError.domain),
            "code": .int(nsError.code),
            "handled": .bool(true)
        ]

        for (key, value) in context.prefix(Self.maxCustomKeys) {
            attrs["custom.\(key)"] = .string(String(value.prefix(Self.maxCustomValueLength)))
        }

        sink.receive(Event(type: "error", seq: sessionManager.nextSequenceNumber(), attrs: attrs))
    }
}
