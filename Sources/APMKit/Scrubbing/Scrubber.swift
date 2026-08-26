import Foundation

/// The mandatory last step before disk write (`CONSTITUTION.md`: Capture → **Scrub** → Disk
/// → Sync, SEC-01). Wraps whatever the pipeline's next stage is — normally an `EventSink`
/// adapter in front of `FileDiskQueue` — so nothing reaches disk through this sink without
/// passing through scrubbing first, structurally rather than just by convention.
///
/// This is the **single unbypassable enforcement point** for SEC-02 (header allowlist) and
/// SEC-03 (query-param value redaction): capture (`NetworkCaptureDelegate`) intentionally
/// captures headers and query strings RAW, unredacted — filtering happens only here, so the
/// guarantee doesn't depend on every future capture path remembering to pre-filter itself.
///
/// Request/response bodies are never scrubbed here because they're never captured in the
/// first place (docs/01 §4.1/§4.2 have no body field) — SEC-04 is satisfied by the schema,
/// not by this type.
public final class Scrubber: EventSink {
    private let downstream: EventSink

    public init(downstream: EventSink) {
        self.downstream = downstream
    }

    public func receive(_ event: Event) {
        var scrubbed = event
        scrubbed.attrs = scrubAttrs(event.attrs)
        scrubbed.ctx.screen = event.ctx.screen.map(PatternRedactor.redact) // docs/02 §6.1: "OTPVerification-0812xxxxxxx"
        downstream.receive(scrubbed)
    }

    private func scrubAttrs(_ attrs: [String: AttributeValue]) -> [String: AttributeValue] {
        var result = attrs

        // SEC-03b + SEC-03: `path` may carry a raw `?query=string` suffix (see
        // `NetworkCaptureDelegate`) — normalize the path portion's id-like segments and
        // redact the query portion's parameter VALUES (names kept, for grouping).
        if case .string(let rawPath)? = result["path"] {
            result["path"] = .string(scrubPathAndQuery(rawPath))
        }

        // SEC-02: request/response headers were captured raw, including Authorization/
        // Cookie — this is the only place they get filtered down to the allowlist.
        for key in ["req_headers", "res_headers"] {
            if case .string(let json)? = result[key] {
                result[key] = .string(scrubHeadersJSON(json))
            }
        }

        // SEC-05/05b: blanket pattern redaction over every remaining string attribute
        // (defense in depth — catches anything structural normalization/filtering above
        // wouldn't, and is what makes this generic across every event type, not just
        // network ones).
        for (key, value) in result {
            if case .string(let string) = value {
                result[key] = .string(PatternRedactor.redact(string))
            }
        }

        return result
    }

    private func scrubPathAndQuery(_ value: String) -> String {
        guard let separator = value.firstIndex(of: "?") else {
            return PathNormalizer.normalize(value)
        }
        let pathPart = String(value[value.startIndex..<separator])
        let queryPart = String(value[value.index(after: separator)...])
        let normalizedPath = PathNormalizer.normalize(pathPart)
        guard !queryPart.isEmpty else { return normalizedPath }
        return "\(normalizedPath)?\(QueryParameterScrubber.scrub(queryString: queryPart))"
    }

    private func scrubHeadersJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let headers = try? JSONDecoder().decode([String: String].self, from: data) else {
            return "{}"
        }
        let filtered = HeaderAllowlist.filter(headers)
        guard let encoded = try? JSONEncoder().encode(filtered), let result = String(data: encoded, encoding: .utf8) else {
            return "{}"
        }
        return result
    }
}
