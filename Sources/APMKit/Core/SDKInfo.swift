import Foundation

/// `envelope.sdk` — docs/01 §2. `health` is `nil` on the fixed `.current` constant (used for
/// the `X-APM-Sdk` upload header, where there's no per-request health to report) and always
/// filled in by `EnvelopeFactory` when it builds the actual envelope `sdk` block.
public struct SDKInfo: Codable, Equatable {
    public var name: String
    public var version: String
    public var health: SDKHealth?

    public init(name: String, version: String, health: SDKHealth? = nil) {
        self.name = name
        self.version = version
        self.health = health
    }

    public static let current = SDKInfo(name: "apmkit-ios", version: "1.0.0")
}

/// `envelope.sdk.health` — docs/01 §2.3, MOB-27 extended. `SelfHealthCounters` already counts
/// written/sent/dropped in-process; this is that snapshot shipped in the envelope, cumulative
/// per install. Counters that never leave the device can't do the job MOB-27 exists for — a
/// silently-rising `dropped`/`written` ratio (queue full, batches rejected) needs to be visible
/// off-device before it becomes an unexplained data hole (docs/01 §2.3, `04` §3.8 alert note).
public struct SDKHealth: Codable, Equatable {
    public var written: Int
    public var sent: Int
    public var dropped: Int
    /// Open-ended by design (docs/01 §2.3: "`drop_reasons` bersifat terbuka") — new reason
    /// strings can be added on the SDK side without a schema change; consumers must tolerate
    /// unrecognized keys rather than failing on them.
    public var dropReasons: [String: Int]

    enum CodingKeys: String, CodingKey {
        case written, sent, dropped
        case dropReasons = "drop_reasons"
    }

    public init(written: Int, sent: Int, dropped: Int, dropReasons: [String: Int]) {
        self.written = written
        self.sent = sent
        self.dropped = dropped
        self.dropReasons = dropReasons
    }
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
