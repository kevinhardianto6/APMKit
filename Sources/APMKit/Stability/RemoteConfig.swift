import Foundation

/// `GET /v1/config` response (docs/01 §9). Fetched at startup, cached locally, with a safe
/// default when neither a fetch nor a cache is available.
///
/// This feature (feat-010, MOB-20/21) only *acts on* `enabled` — the kill switch. `sampling`,
/// `maxBatch`, `uploadIntervalSeconds`, and `disabledFeatures` are parsed and cached (a config
/// fetch is one atomic object; there's no reason to fail parsing over fields this feature
/// doesn't use yet) but deliberately left inert: `sampling` is MOB-22's own row in
/// `FEATURES.md` (P1, not in this feature's scope), and wiring `maxBatch`/
/// `uploadIntervalSeconds` into `SyncEngine.Configuration` is the same kind of scope decision
/// — `CONSTITUTION.md`'s build order says out-of-scope ideas become new rows, not drive-by
/// edits. SEC-20 (remote config may only toggle predefined flags, never change executable
/// behavior) is satisfied by construction: every field here is a fixed, predefined shape
/// decoded from JSON — there is no code path that executes anything the server sends.
public struct RemoteConfig: Codable, Equatable {
    public struct Sampling: Codable, Equatable {
        public var network: Double
        public var breadcrumb: Double

        public init(network: Double, breadcrumb: Double) {
            self.network = network
            self.breadcrumb = breadcrumb
        }
    }

    /// MOB-21: `false` disables the SDK app-wide without a new app release.
    public var enabled: Bool
    public var sampling: Sampling
    public var maxBatch: Int
    public var uploadIntervalSeconds: Double
    public var disabledFeatures: [String]

    enum CodingKeys: String, CodingKey {
        case enabled, sampling
        case maxBatch = "max_batch"
        case uploadIntervalSeconds = "upload_interval_s"
        case disabledFeatures = "disabled_features"
    }

    public init(
        enabled: Bool,
        sampling: Sampling,
        maxBatch: Int,
        uploadIntervalSeconds: Double,
        disabledFeatures: [String]
    ) {
        self.enabled = enabled
        self.sampling = sampling
        self.maxBatch = maxBatch
        self.uploadIntervalSeconds = uploadIntervalSeconds
        self.disabledFeatures = disabledFeatures
    }

    /// Used when no fetch has ever succeeded and there is no cache — docs/01 §9: "fallback ke
    /// default bila gagal". `enabled: true` is the safe choice for that specific case: a
    /// brand-new install that has never reached the config endpoint should behave like normal
    /// SDK operation, not silently disable itself. Values otherwise mirror the documented
    /// example payload.
    public static let safeDefault = RemoteConfig(
        enabled: true,
        sampling: Sampling(network: 1.0, breadcrumb: 1.0),
        maxBatch: 200,
        uploadIntervalSeconds: 30,
        disabledFeatures: []
    )
}
