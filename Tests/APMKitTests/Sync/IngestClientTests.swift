import Testing
import Foundation
@testable import APMKit

@Suite("IngestClient — real POST /v1/ingest, docs/01 §7")
struct IngestClientTests {
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

    @Test("sends the required headers and a gzip body the server can decode back to the exact envelope")
    func sendsCorrectRequestShape() async throws {
        var captured: MockHTTPServer.Request?
        let server = MockHTTPServer { request in
            captured = request
            return .respond(status: 202)
        }
        try server.start()
        defer { server.stop() }

        let client = IngestClient(endpoint: .init(
            url: URL(string: "http://127.0.0.1:\(server.port)/v1/ingest")!,
            appKey: "test-app-key"
        ))
        let envelope = makeEnvelope()
        let outcome = await upload(envelope, with: client)

        #expect(outcome == .accepted)
        let request = try #require(captured)
        #expect(request.method == "POST")
        #expect(request.path == "/v1/ingest")
        #expect(request.headers["X-APM-Key"] == "test-app-key")
        #expect(request.headers["X-APM-Sdk"] == "apmkit-ios/1.0.0")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Content-Encoding"] == "gzip")

        let decompressed = try GunzipHelper.gunzip(request.body)
        let decoded = try JSONDecoder().decode(Envelope.self, from: decompressed)
        #expect(decoded == envelope)
    }

    @Test("maps every docs/01 §7 status code to the correct UploadOutcome")
    func mapsEveryStatusCode() async throws {
        let cases: [(Int, [String: String], UploadOutcome)] = [
            (202, [:], .accepted),
            (400, [:], .rejected),
            (401, [:], .unauthorized),
            (403, [:], .unauthorized),
            (413, [:], .payloadTooLarge),
            (429, ["Retry-After": "17"], .rateLimited(retryAfterSeconds: 17)),
            (500, [:], .serverError),
            (503, [:], .serverError)
        ]

        for (status, headers, expected) in cases {
            let server = MockHTTPServer { _ in .respond(status: status, headers: headers) }
            try server.start()
            defer { server.stop() }

            let client = IngestClient(endpoint: .init(
                url: URL(string: "http://127.0.0.1:\(server.port)/v1/ingest")!,
                appKey: "key"
            ))
            let outcome = await upload(makeEnvelope(), with: client)
            #expect(outcome == expected, "status \(status) should map to \(expected), got \(outcome)")
        }
    }

    @Test("429 without a Retry-After header maps to rateLimited(nil)")
    func rateLimitedWithoutRetryAfterHeader() async throws {
        let server = MockHTTPServer { _ in .respond(status: 429) }
        try server.start()
        defer { server.stop() }

        let client = IngestClient(endpoint: .init(
            url: URL(string: "http://127.0.0.1:\(server.port)/v1/ingest")!,
            appKey: "key"
        ))
        let outcome = await upload(makeEnvelope(), with: client)
        #expect(outcome == .rateLimited(retryAfterSeconds: nil))
    }

    @Test("a connection that never responds maps to transportFailure")
    func hangMapsToTransportFailure() async throws {
        let server = MockHTTPServer { _ in .hang }
        try server.start()
        defer { server.stop() }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 0.3
        let client = IngestClient(
            endpoint: .init(url: URL(string: "http://127.0.0.1:\(server.port)/v1/ingest")!, appKey: "key"),
            session: URLSession(configuration: configuration)
        )
        let outcome = await upload(makeEnvelope(), with: client)
        #expect(outcome == .transportFailure)
    }
}
