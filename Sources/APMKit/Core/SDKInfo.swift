import Foundation

/// `envelope.sdk` — docs/01 §2.
public struct SDKInfo: Codable, Equatable {
    public var name: String
    public var version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }

    public static let current = SDKInfo(name: "apmkit-ios", version: "1.0.0")
}

/// `envelope.app` — docs/01 §2.
public struct AppInfo: Codable, Equatable {
    public var id: String
    public var version: String
    public var build: String

    public init(id: String, version: String, build: String) {
        self.id = id
        self.version = version
        self.build = build
    }

    public static func current(bundle: Bundle = .main) -> AppInfo {
        AppInfo(
            id: bundle.bundleIdentifier ?? "unknown",
            version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            build: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        )
    }
}
