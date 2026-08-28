import Testing
import Foundation
@testable import APMKit

@Suite("EnvelopeFactory")
struct EnvelopeFactoryTests {
    @Test("wraps the given events with injected static context")
    func wrapsEventsWithContext() {
        let sessionManager = SessionManager(initialSessionId: "session-xyz")
        let factory = EnvelopeFactory(
            sessionManager: sessionManager,
            appInfo: { AppInfo(id: "com.example.app", version: "2.0", build: "42") },
            deviceInfo: { DeviceInfo(os: "iOS", osVersion: "17.0", model: "iPhone14,2", locale: "id_ID", timezone: "Asia/Jakarta") },
            installId: { "install-abc" },
            userId: { "user-123" }
        )

        let events = [Event(type: "network", seq: 1)]
        let envelope = factory.makeEnvelope(events: events)

        #expect(envelope.sessionId == "session-xyz")
        #expect(envelope.installId == "install-abc")
        #expect(envelope.userId == "user-123")
        #expect(envelope.app.id == "com.example.app")
        #expect(envelope.events.map(\.eventId) == events.map(\.eventId))
    }

    @Test("threads an isolated UserIdentity-backed userId closure through unchanged")
    func threadsUserIdentityUserIdThrough() throws {
        let suiteName = "EnvelopeFactoryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        UserIdentity.setUser(id: "raw-user-id-value", userDefaults: defaults)

        let factory = EnvelopeFactory(
            sessionManager: SessionManager(),
            userId: { UserIdentity.currentUserId(userDefaults: defaults) }
        )
        let envelope = factory.makeEnvelope(events: [])
        #expect(envelope.userId == "raw-user-id-value")
    }

    @Test("default integrity comes from sessionManager.currentIntegritySnapshot(), cached across calls (feat-008)")
    func defaultIntegrityUsesSessionCachedSnapshot() {
        let sessionManager = SessionManager()
        let factory = EnvelopeFactory(sessionManager: sessionManager)

        // Prime the cache with a known value via the same SessionManager instance the
        // factory holds, then confirm makeEnvelope reflects exactly that cached value
        // rather than recomputing a fresh one.
        let expected = IntegritySnapshot(isEmulator: true, isRooted: true, isDevMode: false, debuggerAttached: false)
        _ = sessionManager.currentIntegritySnapshot(compute: { expected })

        let envelope = factory.makeEnvelope(events: [])
        #expect(envelope.integrity == expected)
    }
}
