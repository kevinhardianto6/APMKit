import Foundation

/// One request's envelope — docs/01 §2. Static per-request context (`sdk`, `app`, `device`,
/// `integrity`, ids) lives here rather than being repeated per event, to save bandwidth and
/// disk (docs/01 §2 intro).
public struct Envelope: Codable, Equatable {
    public var schemaVersion: Int
    public var sdk: SDKInfo
    public var app: AppInfo
    public var device: DeviceInfo
    public var integrity: IntegritySnapshot
    public var installId: String
    public var sessionId: String
    public var userId: String?
    public var events: [Event]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sdk, app, device, integrity
        case installId = "install_id"
        case sessionId = "session_id"
        case userId = "user_id"
        case events
    }

    /// Current, and so far only, wire format version (docs/01 §2). Backend rejects any
    /// version it doesn't recognize with `400` — bump this only alongside a documented
    /// breaking change (docs/01 §11).
    public static let currentSchemaVersion = 1

    public init(
        schemaVersion: Int = Envelope.currentSchemaVersion,
        sdk: SDKInfo = .current,
        app: AppInfo,
        device: DeviceInfo,
        integrity: IntegritySnapshot = .unset,
        installId: String,
        sessionId: String,
        userId: String?,
        events: [Event]
    ) {
        self.schemaVersion = schemaVersion
        self.sdk = sdk
        self.app = app
        self.device = device
        self.integrity = integrity
        self.installId = installId
        self.sessionId = sessionId
        self.userId = userId
        self.events = events
    }
}
