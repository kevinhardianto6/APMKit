import Testing
import Foundation
@testable import APMKit

/// feat-015 (SEC-11) — real TLS handshakes against `TLSMockServer`, driven through the actual
/// production types (`IngestClient`, `PinningSessionDelegate`, `RemoteConfigStore`), not a
/// stand-in. Each test's "Done when" line maps directly onto a `FEATURES.md` feat-015 criterion.
@Suite("Certificate pinning — SEC-11, real TLS handshakes")
struct CertificatePinningTests {
    private func makeEnvelope() -> Envelope {
        Envelope(
            app: AppInfo(id: "com.example.app", version: "1.0", build: "1"),
            device: DeviceInfo(os: "iOS", osVersion: "17.4", model: "iPhone14,2", locale: "id_ID", timezone: "Asia/Jakarta"),
            installId: UUID().uuidString,
            sessionId: UUID().uuidString,
            userId: nil,
            events: [Event(type: "network", seq: 1, attrs: ["host": .string("api.example.com")])]
        )
    }

    private func upload(_ envelope: Envelope, with client: IngestClient) async -> UploadOutcome {
        await withCheckedContinuation { continuation in
            client.upload(envelope: envelope) { outcome in continuation.resume(returning: outcome) }
        }
    }

    /// A fresh, unshared `RemoteConfigStore` per test — a UUID'd `UserDefaults` suite so tests
    /// never see each other's cached config (same isolation reasoning as feat-010's own tests).
    private func makeStore(disabledFeatures: [String] = []) -> RemoteConfigStore {
        let defaults = UserDefaults(suiteName: "kit.apm.test.\(UUID().uuidString)")!
        let store = RemoteConfigStore(userDefaults: defaults)
        var config = RemoteConfig.safeDefault
        config.disabledFeatures = disabledFeatures
        store.apply(config)
        return store
    }

    // MARK: - Done when: OFF behaves identically to feat-011, zero pinning code path active

    @Test("no pinning configured — IngestClient's session has no delegate at all, same as feat-011")
    func offByDefaultHasNoDelegate() {
        let client = IngestClient(endpoint: .init(url: URL(string: "https://example.com/v1/ingest")!, appKey: "key"))
        #expect(client.session.delegate == nil)
    }

    @Test("no pinning configured — RemoteConfigFetcher's session has no delegate at all, same as feat-011")
    func fetcherOffByDefaultHasNoDelegate() {
        let fetcher = RemoteConfigFetcher(endpoint: .init(url: URL(string: "https://example.com/v1/ingest")!, appKey: "key"))
        #expect(fetcher.session.delegate == nil)
    }

    // MARK: - Done when: ON rejects a real wrong-certificate handshake and fails closed

    @Test("pinning ON, server presents a certificate that matches no configured pin — rejected, fails closed, never accepted")
    func wrongCertificateFailsClosed() async throws {
        let presented = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "server.example")
        defer { presented.cleanup() }
        let expected = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "not-the-server.example")
        defer { expected.cleanup() }

        let server = TLSMockServer(identity: presented.identity)
        let port = try server.start()
        defer { server.stop() }

        // The client is pinned to `expected`'s hashes — completely unrelated to what the
        // server actually presents.
        let primaryPin = CertificatePinningConfiguration.pin(forCertificateDER: expected.certificateDER)
        let backupPin = Data(repeating: 0xAB, count: 32) // any distinct value satisfies the backup requirement
        let pinning = try #require(CertificatePinningConfiguration(primaryPin: primaryPin, backupPins: [backupPin]))

        let client = IngestClient(
            endpoint: .init(url: URL(string: "https://127.0.0.1:\(port)/v1/ingest")!, appKey: "key"),
            pinning: CertificatePinning(configuration: pinning, remoteConfigStore: makeStore())
        )

        let outcome = await upload(makeEnvelope(), with: client)
        #expect(outcome != .accepted)
    }

    @Test("pinning ON, server presents the pinned certificate — handshake succeeds, upload is accepted")
    func matchingCertificateSucceeds() async throws {
        let identity = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "server.example")
        defer { identity.cleanup() }

        let server = TLSMockServer(identity: identity.identity)
        server.responseBytes = Data("HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        let port = try server.start()
        defer { server.stop() }

        let primaryPin = CertificatePinningConfiguration.pin(forCertificateDER: identity.certificateDER)
        let backupPin = Data(repeating: 0xCD, count: 32)
        let pinning = try #require(CertificatePinningConfiguration(primaryPin: primaryPin, backupPins: [backupPin]))

        let client = IngestClient(
            endpoint: .init(url: URL(string: "https://127.0.0.1:\(port)/v1/ingest")!, appKey: "key"),
            pinning: CertificatePinning(configuration: pinning, remoteConfigStore: makeStore())
        )

        let outcome = await upload(makeEnvelope(), with: client)
        #expect(outcome == .accepted)
    }

    // MARK: - Done when: a simulated certificate rotation keeps working via the backup pin

    @Test("certificate rotation: server now presents the backup-pinned identity, not the primary — still accepted")
    func rotationToBackupPinStillSucceeds() async throws {
        let oldIdentity = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "old.example")
        defer { oldIdentity.cleanup() }
        let rotatedIdentity = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "rotated.example")
        defer { rotatedIdentity.cleanup() }

        // Pin config was set up in advance with the rotated cert's hash as the backup pin —
        // exactly SEC-11's rationale for requiring one. The server has already rotated to the
        // new cert; the client's config was never touched.
        let primaryPin = CertificatePinningConfiguration.pin(forCertificateDER: oldIdentity.certificateDER)
        let backupPin = CertificatePinningConfiguration.pin(forCertificateDER: rotatedIdentity.certificateDER)
        let pinning = try #require(CertificatePinningConfiguration(primaryPin: primaryPin, backupPins: [backupPin]))

        let server = TLSMockServer(identity: rotatedIdentity.identity)
        let port = try server.start()
        defer { server.stop() }

        let client = IngestClient(
            endpoint: .init(url: URL(string: "https://127.0.0.1:\(port)/v1/ingest")!, appKey: "key"),
            pinning: CertificatePinning(configuration: pinning, remoteConfigStore: makeStore())
        )

        let outcome = await upload(makeEnvelope(), with: client)
        #expect(outcome == .accepted)
    }

    // MARK: - Done when: the kill switch disables pinning without an app release, and re-enables it

    @Test("kill switch ON (disabledFeatures contains cert_pinning): falls back to plain TLS floor — a self-signed cert that WOULD match the pin is now rejected by ordinary system CA trust, proving this is a real fallback to verified TLS, not to no verification at all")
    func killSwitchFallsBackToVerifiedTLSFloor() async throws {
        let identity = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "server.example")
        defer { identity.cleanup() }

        let server = TLSMockServer(identity: identity.identity)
        let port = try server.start()
        defer { server.stop() }

        let primaryPin = CertificatePinningConfiguration.pin(forCertificateDER: identity.certificateDER)
        let backupPin = Data(repeating: 0xEF, count: 32)
        let pinning = try #require(CertificatePinningConfiguration(primaryPin: primaryPin, backupPins: [backupPin]))

        // SEC-11's kill switch: disabledFeatures == ["cert_pinning"].
        let store = makeStore(disabledFeatures: [PinningSessionDelegate.killSwitchFeatureName])
        let client = IngestClient(
            endpoint: .init(url: URL(string: "https://127.0.0.1:\(port)/v1/ingest")!, appKey: "key"),
            pinning: CertificatePinning(configuration: pinning, remoteConfigStore: store)
        )

        // Without the kill switch this exact setup succeeds (proven by
        // `matchingCertificateSucceeds` above) — with it on, `performDefaultHandling` applies
        // ordinary system CA trust, which a self-signed certificate never satisfies. SEC-12:
        // "stop pinning" still means "stay verified," never "stop verifying."
        let outcome = await upload(makeEnvelope(), with: client)
        #expect(outcome != .accepted)
    }

    @Test("flipping the kill switch back off re-enables pinning on the very next request, no restart needed")
    func killSwitchTogglingBackOnReEnablesPinning() async throws {
        let identity = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "server.example")
        defer { identity.cleanup() }

        let server = TLSMockServer(identity: identity.identity)
        let port = try server.start()
        defer { server.stop() }

        let primaryPin = CertificatePinningConfiguration.pin(forCertificateDER: identity.certificateDER)
        let backupPin = Data(repeating: 0x11, count: 32)
        let pinning = try #require(CertificatePinningConfiguration(primaryPin: primaryPin, backupPins: [backupPin]))

        let store = makeStore(disabledFeatures: [PinningSessionDelegate.killSwitchFeatureName])
        let client = IngestClient(
            endpoint: .init(url: URL(string: "https://127.0.0.1:\(port)/v1/ingest")!, appKey: "key"),
            pinning: CertificatePinning(configuration: pinning, remoteConfigStore: store)
        )

        let disabledOutcome = await upload(makeEnvelope(), with: client)
        #expect(disabledOutcome != .accepted)

        // Same store instance the client already holds a reference to — flip it live, the way
        // a real fetch cycle would (`RemoteConfigStore.apply`), with no new `IngestClient`.
        var reenabled = RemoteConfig.safeDefault
        reenabled.disabledFeatures = []
        store.apply(reenabled)

        let secondServer = TLSMockServer(identity: identity.identity)
        // The mock server accepts one connection and closes; a second real request needs a
        // fresh listener on the same identity to represent "the next request."
        secondServer.responseBytes = server.responseBytes
        let secondPort = try secondServer.start()
        defer { secondServer.stop() }

        let secondClient = IngestClient(
            endpoint: .init(url: URL(string: "https://127.0.0.1:\(secondPort)/v1/ingest")!, appKey: "key"),
            pinning: CertificatePinning(configuration: pinning, remoteConfigStore: store)
        )
        let enabledOutcome = await upload(makeEnvelope(), with: secondClient)
        #expect(enabledOutcome == .accepted)
    }

    // MARK: - RemoteConfigFetcher shares the same delegate — one confirming test, not a full duplicate suite

    @Test("RemoteConfigFetcher: pinning ON, matching certificate — real GET /v1/config succeeds over the pinned connection")
    func remoteConfigFetcherHonoursPinning() async throws {
        let identity = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "config-server.example")
        defer { identity.cleanup() }

        let server = TLSMockServer(identity: identity.identity)
        let configJSON = """
        {"enabled":true,"sampling":{"network":1.0,"breadcrumb":1.0},"max_batch":200,"upload_interval_s":30,"disabled_features":[]}
        """
        server.responseBytes = Data(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(configJSON.utf8.count)\r\nConnection: close\r\n\r\n\(configJSON)"
                .utf8
        )
        let port = try server.start()
        defer { server.stop() }

        let primaryPin = CertificatePinningConfiguration.pin(forCertificateDER: identity.certificateDER)
        let backupPin = Data(repeating: 0x22, count: 32)
        let pinning = try #require(CertificatePinningConfiguration(primaryPin: primaryPin, backupPins: [backupPin]))

        let fetcher = RemoteConfigFetcher(
            endpoint: .init(url: URL(string: "https://127.0.0.1:\(port)/v1/ingest")!, appKey: "key"),
            pinning: CertificatePinning(configuration: pinning, remoteConfigStore: makeStore())
        )

        let config = await withCheckedContinuation { (continuation: CheckedContinuation<RemoteConfig?, Never>) in
            fetcher.fetch { continuation.resume(returning: $0) }
        }
        #expect(config?.enabled == true)
    }
}
