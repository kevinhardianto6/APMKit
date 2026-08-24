import Foundation

/// `event.ctx` — docs/01 §3. Volatile context that can change within one session, unlike
/// the envelope's static context.
public struct EventContext: Codable, Equatable {
    public var connectivity: String?
    public var screen: String?
    public var appState: String?
    public var lowPower: Bool?

    enum CodingKeys: String, CodingKey {
        case connectivity, screen
        case appState = "app_state"
        case lowPower = "low_power"
    }

    public init(
        connectivity: String? = nil,
        screen: String? = nil,
        appState: String? = nil,
        lowPower: Bool? = nil
    ) {
        self.connectivity = connectivity
        self.screen = screen
        self.appState = appState
        self.lowPower = lowPower
    }
}
