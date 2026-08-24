import Testing
import Foundation
@testable import APMKit

@Suite("Session lifecycle — docs/01 §2, 'session resets after >30s background'")
struct SessionManagerTests {
    @Test("session_id is stable across a short background (<= 30s)")
    func shortBackgroundKeepsSameSession() {
        let manager = SessionManager()
        let original = manager.sessionId
        let t0 = Date()

        manager.appDidEnterBackground(at: t0)
        manager.appWillEnterForeground(at: t0.addingTimeInterval(30))

        #expect(manager.sessionId == original)
    }

    @Test("session_id rotates after a background longer than 30s")
    func longBackgroundRotatesSession() {
        let manager = SessionManager()
        let original = manager.sessionId
        let t0 = Date()

        manager.appDidEnterBackground(at: t0)
        manager.appWillEnterForeground(at: t0.addingTimeInterval(30.001))

        #expect(manager.sessionId != original)
    }

    @Test("seq counter resets to start over on session rotation")
    func seqResetsOnRotation() {
        let manager = SessionManager()
        _ = manager.nextSequenceNumber() // 1
        _ = manager.nextSequenceNumber() // 2
        let t0 = Date()

        manager.appDidEnterBackground(at: t0)
        manager.appWillEnterForeground(at: t0.addingTimeInterval(31))

        #expect(manager.nextSequenceNumber() == 1)
    }

    @Test("seq counter is monotonic within a session")
    func seqIsMonotonic() {
        let manager = SessionManager()
        let sequence = (0..<5).map { _ in manager.nextSequenceNumber() }
        #expect(sequence == [1, 2, 3, 4, 5])
    }

    @Test("foreground without a prior background is a no-op")
    func foregroundWithoutBackgroundIsNoOp() {
        let manager = SessionManager()
        let original = manager.sessionId
        manager.appWillEnterForeground()
        #expect(manager.sessionId == original)
    }
}
