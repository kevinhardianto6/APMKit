import Foundation

/// Holds the current `RemoteConfig` (docs/01 §9) for synchronous, thread-safe reads by
/// anything that needs to check the kill switch or other config right now — `KillSwitch`,
/// `SyncEngine`'s `isEnabled` closure — without blocking on network I/O.
///
/// Seeded synchronously at `init` from the last cached value (`UserDefaults`), or
/// `.safeDefault` if none exists yet — this is what "cache lokal dan fallback ke default bila
/// gagal" (docs/01 §9) means in practice: a fetch (`APM.fetchRemoteConfig`) is a background
/// operation that *updates* this store when it completes; it is never on the critical path
/// for "can I capture this event right now."
public final class RemoteConfigStore {
    private static let cacheKey = "kit.apm.remote_config_cache"

    private let userDefaults: UserDefaults
    private let lock = NSLock()
    private var currentValue: RemoteConfig
    private let encoder = JSONEncoder()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(RemoteConfig.self, from: data) {
            self.currentValue = cached
        } else {
            self.currentValue = .safeDefault
        }
    }

    public var current: RemoteConfig {
        lock.lock(); defer { lock.unlock() }
        return currentValue
    }

    /// Applies a fetch result. `nil` (the fetch failed — network error, non-200, malformed
    /// body) leaves the existing in-memory value untouched — whatever was cached, or
    /// `.safeDefault` if this is the very first launch. A successful fetch updates the
    /// in-memory value immediately *and* persists it, so the next launch's fallback (before
    /// its own fetch completes) is this value, not an older one.
    public func apply(_ fetched: RemoteConfig?) {
        guard let fetched else { return }
        lock.lock()
        currentValue = fetched
        lock.unlock()
        if let data = try? encoder.encode(fetched) {
            userDefaults.set(data, forKey: Self.cacheKey)
        }
    }
}
