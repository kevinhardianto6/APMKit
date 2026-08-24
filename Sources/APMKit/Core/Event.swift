import Foundation

/// One captured event — docs/01 §3. `attrs` shape varies by `type` (§4.1–4.6); those
/// per-type attribute sets are built by the features that produce them (network, crash, …).
public struct Event: Codable, Equatable {
    public var eventId: String
    public var type: String
    public var tsClient: String
    public var seq: Int
    public var attrs: [String: AttributeValue]
    public var ctx: EventContext

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case type
        case tsClient = "ts_client"
        case seq, attrs, ctx
    }

    public init(
        eventId: String = UUID().uuidString,
        type: String,
        timestamp: Date = Date(),
        seq: Int,
        attrs: [String: AttributeValue] = [:],
        ctx: EventContext = EventContext()
    ) {
        self.eventId = eventId
        self.type = type
        self.tsClient = ISO8601Formatting.string(from: timestamp)
        self.seq = seq
        self.attrs = attrs
        self.ctx = ctx
    }
}
