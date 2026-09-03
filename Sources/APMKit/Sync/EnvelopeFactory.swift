import Foundation

/// Wraps a batch of events with the static envelope context (docs/01 §2) at upload time.
/// Every field is injectable so `SyncEngine` doesn't need to know how any of them are
/// produced — `user_id`/`user_id_source` default to `UserIdentity.currentUserIdentity()`
/// (feat-006, extended 2026-09-02: the explicit value from `APM.setUser`, or a stable
/// per-install fallback, plus which one it was — docs/01 §2.2); `integrity` defaults to
/// `sessionManager.currentIntegritySnapshot()` (feat-008: real detection, cached once per
/// session by `SessionManager` itself); `sdk.health` (docs/01 §2.3) is read fresh from
/// `selfHealth.snapshot()` on every call, since it's cumulative counters, not static context.
public struct EnvelopeFactory {
    private let sessionManager: SessionManager
    private let appInfo: () -> AppInfo
    private let deviceInfo: () -> DeviceInfo
    private let integrity: () -> IntegritySnapshot
    private let installId: () -> String
    /// A single closure returning both `user_id` and `user_id_source` together — not two
    /// separate closures — so they can never be read from two different moments in time and
    /// disagree about which branch (`setUser` vs. generated fallback) actually produced the id.
    private let userIdentity: () -> (id: String, source: UserIdSource)
    private let selfHealth: SelfHealthCounters

    public init(
        sessionManager: SessionManager,
        appInfo: @escaping () -> AppInfo = { AppInfo.current() },
        deviceInfo: @escaping () -> DeviceInfo = { DeviceInfo.current() },
        integrity: (() -> IntegritySnapshot)? = nil,
        installId: @escaping () -> String = { InstallIdentity.current() },
        userIdentity: @escaping () -> (id: String, source: UserIdSource) = { UserIdentity.currentUserIdentity() },
        selfHealth: SelfHealthCounters = .shared
    ) {
        self.sessionManager = sessionManager
        self.appInfo = appInfo
        self.deviceInfo = deviceInfo
        // Can't reference `sessionManager` in a parameter default expression, so the
        // session-cached-snapshot default is resolved here instead of at the call site.
        self.integrity = integrity ?? { sessionManager.currentIntegritySnapshot() }
        self.installId = installId
        self.userIdentity = userIdentity
        self.selfHealth = selfHealth
    }

    public func makeEnvelope(events: [Event]) -> Envelope {
        let (userId, userIdSource) = userIdentity()
        let health = selfHealth.snapshot()

        return Envelope(
            sdk: SDKInfo(
                name: SDKInfo.current.name,
                version: SDKInfo.current.version,
                health: SDKHealth(written: health.written, sent: health.sent, dropped: health.dropped, dropReasons: health.dropReasons)
            ),
            app: appInfo(),
            device: deviceInfo(),
            integrity: integrity(),
            installId: installId(),
            sessionId: sessionManager.sessionId,
            userId: userId,
            userIdSource: userIdSource,
            events: events
        )
    }
}
