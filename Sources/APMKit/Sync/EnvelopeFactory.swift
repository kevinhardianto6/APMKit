import Foundation

/// Wraps a batch of events with the static envelope context (docs/01 §2) at upload time.
/// Every field is injectable so `SyncEngine` doesn't need to know how any of them are
/// produced — `user_id` defaults to `UserIdentity.currentUserId()` (feat-006: the explicit
/// value from `APM.setUser`, or a stable per-install fallback); `integrity` defaults to
/// `.unset` since real detection lands in feat-008.
public struct EnvelopeFactory {
    private let sessionManager: SessionManager
    private let appInfo: () -> AppInfo
    private let deviceInfo: () -> DeviceInfo
    private let integrity: () -> IntegritySnapshot
    private let installId: () -> String
    private let userId: () -> String?

    public init(
        sessionManager: SessionManager,
        appInfo: @escaping () -> AppInfo = { AppInfo.current() },
        deviceInfo: @escaping () -> DeviceInfo = { DeviceInfo.current() },
        integrity: @escaping () -> IntegritySnapshot = { .unset },
        installId: @escaping () -> String = { InstallIdentity.current() },
        userId: @escaping () -> String? = { UserIdentity.currentUserId() }
    ) {
        self.sessionManager = sessionManager
        self.appInfo = appInfo
        self.deviceInfo = deviceInfo
        self.integrity = integrity
        self.installId = installId
        self.userId = userId
    }

    public func makeEnvelope(events: [Event]) -> Envelope {
        Envelope(
            app: appInfo(),
            device: deviceInfo(),
            integrity: integrity(),
            installId: installId(),
            sessionId: sessionManager.sessionId,
            userId: userId(),
            events: events
        )
    }
}
