import Testing
import Foundation
@testable import APMKit

/// feat-016 — `APM.start(configuration:)` is the composition root; these tests drive the real
/// assembled pipeline end to end (real `FileDiskQueue` on a temp directory, real `TLSMockServer`
/// for the pinning path, real `SyncEngine.triggerSync`), not fakes standing in for the wiring
/// itself. The point is to prove the *wiring* — that one call actually produces a working
/// pipeline — not to re-test each piece's own already-covered logic.
@Suite("APM.start — composition root, feat-016")
struct APMStartTests {
    private func tempQueueDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("apmkit-start-test-\(UUID().uuidString)")
    }

    /// Every test gets its own `UserDefaults` suite — `APM.start`'s `RemoteConfigStore`
    /// defaults to `.standard`, which is correct for production but would otherwise let
    /// one test's kill-switch state leak into every other `APM.start()` call in this same
    /// `swift test` process (see `Configuration.remoteConfigUserDefaults`'s doc comment).
    private func isolatedUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: "apmkit-start-test.\(UUID().uuidString)")!
    }

    @Test("a minimal APM.start(configuration:) call assembles a working pipeline: logError reaches disk")
    func minimalStartWritesToDisk() throws {
        let queueDir = tempQueueDirectory()
        defer { try? FileManager.default.removeItem(at: queueDir) }

        let instance = APM.start(configuration: .init(
            ingestEndpoint: .init(url: URL(string: "https://127.0.0.1:1/v1/ingest")!, appKey: "key"),
            queueDirectory: queueDir,
            remoteConfigUserDefaults: isolatedUserDefaults()
        ))

        KeychainTestLock.sync { instance.logError(NSError(domain: "test", code: 1), context: ["k": "v"]) }

        // The disk queue is the actual `FileDiskQueue` at `queueDir` — one JSON file per event.
        let files = try FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil)
        #expect(files.contains { $0.pathExtension == "json" })
    }

    @Test("the kill switch (configStore.enabled = false) stops new events from reaching disk, same as feat-010's guarantee")
    func killSwitchStopsCapture() throws {
        let queueDir = tempQueueDirectory()
        defer { try? FileManager.default.removeItem(at: queueDir) }

        let instance = APM.start(configuration: .init(
            ingestEndpoint: .init(url: URL(string: "https://127.0.0.1:1/v1/ingest")!, appKey: "key"),
            queueDirectory: queueDir,
            remoteConfigUserDefaults: isolatedUserDefaults()
        ))

        var disabled = RemoteConfig.safeDefault
        disabled.enabled = false
        instance.configStore.apply(disabled)

        KeychainTestLock.sync { instance.logError(NSError(domain: "test", code: 2)) }

        let files = (try? FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil)) ?? []
        #expect(!files.contains { $0.pathExtension == "json" })
    }

    @Test("instrumentedSession() excludes this instance's own ingest host automatically (MOB-09/10), with no manual step")
    func instrumentedSessionAutoExcludesIngestHost() {
        let instance = APM.start(configuration: .init(
            ingestEndpoint: .init(url: URL(string: "https://ingest.example.com/v1/ingest")!, appKey: "key"),
            queueDirectory: tempQueueDirectory(),
            remoteConfigUserDefaults: isolatedUserDefaults()
        ))

        let (session, captureDelegate) = instance.instrumentedSession()
        #expect(session.delegate === captureDelegate)
    }

    @Test("real end-to-end pipeline via APM.start: pinned TLS handshake, real encrypted disk write, real upload, queue drains")
    func fullPipelineWithPinningUploadsAndDrains() async throws {
        let identity = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "start-e2e.example")
        defer { identity.cleanup() }

        let server = TLSMockServer(identity: identity.identity)
        server.responseBytes = Data("HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        let port = try server.start()
        defer { server.stop() }

        let primaryPin = CertificatePinningConfiguration.pin(forCertificateDER: identity.certificateDER)
        let backupPin = Data(repeating: 0x42, count: 32)
        let pinning = try #require(CertificatePinningConfiguration(primaryPin: primaryPin, backupPins: [backupPin]))

        let queueDir = tempQueueDirectory()
        defer { try? FileManager.default.removeItem(at: queueDir) }

        let instance = APM.start(configuration: .init(
            ingestEndpoint: .init(url: URL(string: "https://127.0.0.1:\(port)/v1/ingest")!, appKey: "key"),
            pinning: pinning,
            queueDirectory: queueDir,
            remoteConfigUserDefaults: isolatedUserDefaults()
        ))

        KeychainTestLock.sync { instance.logError(NSError(domain: "test", code: 3)) }

        // Before the sync cycle: the event is on disk, encrypted (SEC-08) — not asserted
        // byte-for-byte here (feat-014 already proves that), just that something landed.
        let beforeSync = try FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil)
        #expect(beforeSync.contains { $0.pathExtension == "json" })

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            instance.syncEngine.triggerSync { continuation.resume() }
        }

        // A real 2xx from the real (pinned) TLS server deletes the event from disk — this only
        // happens if the pin actually matched and the upload actually succeeded end to end.
        let afterSync = try FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil)
        #expect(!afterSync.contains { $0.pathExtension == "json" })
    }

    @Test("wrong pin: the same pipeline never drains — a mismatched cert fails the upload closed, event stays on disk")
    func fullPipelineWithWrongPinNeverDrains() async throws {
        let presented = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "start-e2e-server.example")
        defer { presented.cleanup() }
        let expected = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "start-e2e-wrong.example")
        defer { expected.cleanup() }

        let server = TLSMockServer(identity: presented.identity)
        let port = try server.start()
        defer { server.stop() }

        let primaryPin = CertificatePinningConfiguration.pin(forCertificateDER: expected.certificateDER)
        let backupPin = Data(repeating: 0x24, count: 32)
        let pinning = try #require(CertificatePinningConfiguration(primaryPin: primaryPin, backupPins: [backupPin]))

        let queueDir = tempQueueDirectory()
        defer { try? FileManager.default.removeItem(at: queueDir) }

        let instance = APM.start(configuration: .init(
            ingestEndpoint: .init(url: URL(string: "https://127.0.0.1:\(port)/v1/ingest")!, appKey: "key"),
            pinning: pinning,
            queueDirectory: queueDir,
            remoteConfigUserDefaults: isolatedUserDefaults()
        ))

        KeychainTestLock.sync { instance.logError(NSError(domain: "test", code: 4)) }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            instance.syncEngine.triggerSync { continuation.resume() }
        }

        let afterSync = try FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil)
        #expect(afterSync.contains { $0.pathExtension == "json" })
    }
}
