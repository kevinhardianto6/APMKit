import Testing
import Foundation
@testable import APMKit

@Suite("RemoteConfig — docs/01 §9 GET /v1/config schema")
struct RemoteConfigTests {
    @Test("decodes the exact documented example payload")
    func decodesDocumentedExample() throws {
        let json = """
        { "enabled": true,
          "sampling": { "network": 1.0, "breadcrumb": 1.0 },
          "max_batch": 200,
          "upload_interval_s": 30,
          "disabled_features": [] }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(RemoteConfig.self, from: json)

        #expect(config.enabled == true)
        #expect(config.sampling.network == 1.0)
        #expect(config.sampling.breadcrumb == 1.0)
        #expect(config.maxBatch == 200)
        #expect(config.uploadIntervalSeconds == 30)
        #expect(config.disabledFeatures.isEmpty)
    }

    @Test("round-trips through encode/decode")
    func roundTrips() throws {
        let config = RemoteConfig(
            enabled: false,
            sampling: .init(network: 0.5, breadcrumb: 0.1),
            maxBatch: 50,
            uploadIntervalSeconds: 60,
            disabledFeatures: ["hang_detection"]
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RemoteConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test("safeDefault is enabled — a fresh install with no fetch and no cache must not silently disable itself")
    func safeDefaultIsEnabled() {
        #expect(RemoteConfig.safeDefault.enabled == true)
    }
}

@Suite("RemoteConfigStore — cache + safe-default fallback (docs/01 §9)")
struct RemoteConfigStoreTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "RemoteConfigStoreTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test("no cache yet: current is .safeDefault")
    func noCacheFallsBackToSafeDefault() {
        let store = RemoteConfigStore(userDefaults: freshDefaults())
        #expect(store.current == .safeDefault)
    }

    @Test("apply(_:) with a successful fetch updates current immediately")
    func applyUpdatesCurrent() {
        let store = RemoteConfigStore(userDefaults: freshDefaults())
        let fetched = RemoteConfig(enabled: false, sampling: .init(network: 1, breadcrumb: 1), maxBatch: 200, uploadIntervalSeconds: 30, disabledFeatures: [])

        store.apply(fetched)

        #expect(store.current == fetched)
    }

    @Test("apply(nil) — a failed fetch — leaves the existing value untouched")
    func applyNilLeavesExistingValueUntouched() {
        let store = RemoteConfigStore(userDefaults: freshDefaults())
        let fetched = RemoteConfig(enabled: false, sampling: .init(network: 1, breadcrumb: 1), maxBatch: 200, uploadIntervalSeconds: 30, disabledFeatures: [])
        store.apply(fetched)

        store.apply(nil)

        #expect(store.current == fetched) // still the last successful fetch, not reset to safeDefault
    }

    @Test("a new store instance over the same UserDefaults picks up the previous instance's cached value")
    func newInstanceSeesPreviousInstancesCache() {
        let defaults = freshDefaults()
        let fetched = RemoteConfig(enabled: false, sampling: .init(network: 0.2, breadcrumb: 0.3), maxBatch: 10, uploadIntervalSeconds: 5, disabledFeatures: ["x"])

        RemoteConfigStore(userDefaults: defaults).apply(fetched)
        let reopened = RemoteConfigStore(userDefaults: defaults)

        #expect(reopened.current == fetched)
    }
}

@Suite("RemoteConfigFetcher — real GET /v1/config")
struct RemoteConfigFetcherTests {
    private func fetch(_ fetcher: RemoteConfigFetcher) async -> RemoteConfig? {
        await withCheckedContinuation { continuation in
            fetcher.fetch { continuation.resume(returning: $0) }
        }
    }

    @Test("a 200 with a valid body decodes to the expected config, with the correct headers/path sent")
    func successfulFetchDecodesConfig() async throws {
        var captured: MockHTTPServer.Request?
        let body = """
        { "enabled": false,
          "sampling": { "network": 0.5, "breadcrumb": 1.0 },
          "max_batch": 100,
          "upload_interval_s": 45,
          "disabled_features": ["hang_detection"] }
        """.data(using: .utf8)!

        let server = MockHTTPServer { request in
            captured = request
            return .respond(status: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        try server.start()
        defer { server.stop() }

        let fetcher = RemoteConfigFetcher(endpoint: .init(
            url: URL(string: "http://127.0.0.1:\(server.port)/v1/ingest")!,
            appKey: "test-app-key"
        ))
        let config = await fetch(fetcher)

        let request = try #require(captured)
        #expect(request.method == "GET")
        #expect(request.path == "/v1/config") // sibling of /v1/ingest, same host — MOB-10 anti-loop still applies
        #expect(request.headers["X-APM-Key"] == "test-app-key")

        #expect(config?.enabled == false)
        #expect(config?.maxBatch == 100)
        #expect(config?.disabledFeatures == ["hang_detection"])
    }

    @Test("a non-200 response yields nil, not a crash or a partial config")
    func non200YieldsNil() async throws {
        let server = MockHTTPServer { _ in .respond(status: 500) }
        try server.start()
        defer { server.stop() }

        let fetcher = RemoteConfigFetcher(endpoint: .init(
            url: URL(string: "http://127.0.0.1:\(server.port)/v1/ingest")!,
            appKey: "key"
        ))
        let config = await fetch(fetcher)

        #expect(config == nil)
    }

    @Test("a transport failure (offline/timeout) yields nil")
    func transportFailureYieldsNil() async {
        let fetcher = RemoteConfigFetcher(endpoint: .init(
            url: URL(string: "http://127.0.0.1:1")!, // nothing listening
            appKey: "key"
        ))
        let config = await fetch(fetcher)

        #expect(config == nil)
    }

    @Test("MOB-09 anti-loop: the default session has no delegate, matching IngestClient")
    func defaultSessionHasNoDelegate() {
        let fetcher = RemoteConfigFetcher(endpoint: .init(url: URL(string: "http://example.com/v1/ingest")!, appKey: "key"))
        #expect(fetcher.session.delegate == nil)
    }
}
