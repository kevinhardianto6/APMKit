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
    private let breadcrumbs: BreadcrumbRingBuffer

    /// docs/01 §4.4: "Maks 20 key, masing-masing ≤ 256 karakter."
    private static let maxCustomKeys = 20
    private static let maxCustomValueLength = 256

    public init(sink: EventSink, sessionManager: SessionManager, breadcrumbs: BreadcrumbRingBuffer = .shared) {
        self.sink = sink
        self.sessionManager = sessionManager
        self.breadcrumbs = breadcrumbs
    }

    /// Reports a handled error (docs/01 §4.4: `handled` is always `true` for this path —
    /// unhandled crashes are feat-009's domain, wrapping KSCrash).
    ///
    /// `file`/`function`/`line` (docs/01 §4.4, docs/02 MOB-11b) default to `#fileID`/
    /// `#function`/`#line` **evaluated at this call**, not forwarded from further up the
    /// stack — callers that wrap this (`APM.logError`, `APMInstance.logError`) must declare
    /// the same three defaults themselves and pass them through explicitly, or the captured
    /// location collapses to the wrapper's own file instead of the real call site. **Must stay
    /// `#fileID`, never `#file`**: `#file` is the absolute build-machine path (leaks the
    /// developer's username and directory layout into the monitoring backend); SEC-05's
    /// scrubbing patterns target phone numbers/emails/JWTs and would not catch this. `#fileID`
    /// gives the safe `Module/File.swift` short form.
    public func logError(
        _ error: Error,
        context: [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        let nsError = error as NSError

        var attrs: [String: AttributeValue] = [
            "name": .string(String(describing: type(of: error))),
            "message": .string(nsError.localizedDescription),
            "domain": .string(nsError.domain),
            "code": .int(nsError.code),
            "handled": .bool(true),
            "source_file": .string(file),
            "source_function": .string(function),
            "source_line": .int(line),
            "breadcrumbs": .string(breadcrumbsJSON())
        ]

        for (key, value) in context.prefix(Self.maxCustomKeys) {
            attrs["custom.\(key)"] = .string(String(value.prefix(Self.maxCustomValueLength)))
        }

        sink.receive(Event(type: "error", seq: sessionManager.nextSequenceNumber(), attrs: attrs))
    }

    /// MOB-13: the last 100 breadcrumbs, attached as a snapshot. JSON-encoded since
    /// `AttributeValue` only carries scalars — same pattern as feat-004's `req_headers`.
    /// No redaction happens here: this string flows into `attrs` above like everything else
    /// and gets caught by `Scrubber`'s blanket pass, the same as any other event attribute.
    private func breadcrumbsJSON() -> String {
        guard let data = try? JSONEncoder().encode(breadcrumbs.snapshot()),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}
