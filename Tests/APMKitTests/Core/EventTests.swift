import Testing
import Foundation
@testable import APMKit

@Suite("Event JSON shape — docs/01 §3")
struct EventTests {
    @Test("encodes the exact event field set with snake_case keys")
    func encodesExactShape() throws {
        let timestamp = ISO8601Formatting.date(from: "2026-07-24T09:12:33.412Z")!
        let event = Event(
            eventId: "3f2b1c8a-0000-0000-0000-000000000000",
            type: "network_failure",
            timestamp: timestamp,
            seq: 1043,
            attrs: ["host": "api.example.com", "duration_ms": 812],
            ctx: EventContext(
                connectivity: "wifi", screen: "CheckoutViewController",
                appState: "foreground", lowPower: false
            )
        )

        let data = try JSONEncoder().encode(event)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["event_id"] as? String == "3f2b1c8a-0000-0000-0000-000000000000")
        #expect(json["type"] as? String == "network_failure")
        #expect(json["ts_client"] as? String == "2026-07-24T09:12:33.412Z")
        #expect(json["seq"] as? Int == 1043)

        let attrs = try #require(json["attrs"] as? [String: Any])
        #expect(attrs["host"] as? String == "api.example.com")
        #expect(attrs["duration_ms"] as? Int == 812)

        let ctx = try #require(json["ctx"] as? [String: Any])
        #expect(ctx["connectivity"] as? String == "wifi")
        #expect(ctx["screen"] as? String == "CheckoutViewController")
        #expect(ctx["app_state"] as? String == "foreground")
        #expect(ctx["low_power"] as? Bool == false)

        #expect(Set(json.keys) == ["event_id", "type", "ts_client", "seq", "attrs", "ctx"])
    }

    @Test("event_id defaults to a fresh UUID v4 per event")
    func eventIdDefaultsToUUID() {
        let a = Event(type: "breadcrumb", seq: 1)
        let b = Event(type: "breadcrumb", seq: 2)
        #expect(a.eventId != b.eventId)
        #expect(UUID(uuidString: a.eventId) != nil)
    }

    @Test("AttributeValue round-trips string, int, double, bool")
    func attributeValueRoundTrips() throws {
        let event = Event(
            type: "error",
            seq: 1,
            attrs: [
                "s": "text",
                "i": 42,
                "d": 3.14,
                "b": true
            ]
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(Event.self, from: data)
        #expect(decoded.attrs["s"] == .string("text"))
        #expect(decoded.attrs["i"] == .int(42))
        #expect(decoded.attrs["d"] == .double(3.14))
        #expect(decoded.attrs["b"] == .bool(true))
    }

    @Test("ctx fields are optional and omit-friendly when absent")
    func ctxOptionalFieldsDecodeAsNil() throws {
        let json = """
        {"event_id":"e","type":"log","ts_client":"2026-01-01T00:00:00.000Z","seq":1,"attrs":{},"ctx":{}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Event.self, from: json)
        #expect(decoded.ctx.connectivity == nil)
        #expect(decoded.ctx.screen == nil)
        #expect(decoded.ctx.appState == nil)
        #expect(decoded.ctx.lowPower == nil)
    }
}
