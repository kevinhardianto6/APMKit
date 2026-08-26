import Testing
import Foundation
@testable import APMKit

/// Full pipeline, real components: `NetworkCaptureDelegate` → `Scrubber` → `FileDiskQueue`.
/// Unlike `ScrubberTests`' end-to-end test (which hand-builds an `Event`), this drives an
/// actual `URLRequest` with a PII-bearing query string and an `Authorization` header through
/// a real loopback server, proving the feat-003/feat-004 amendment (2026-08-24: capture raw
/// in feat-003, redact only in the Scrubber) holds for the real capture path, not just a
/// synthetic one.
@Suite("Pipeline end-to-end — NetworkCaptureDelegate → Scrubber → FileDiskQueue")
struct PipelineEndToEndTests {
    @Test("a request with a PII query value and an Authorization header never reaches disk unredacted")
    func piiNeverReachesDisk() async throws {
        let server = MockHTTPServer { _, _ in .respond(status: 200, body: Data("ok".utf8)) }
        try server.start()
        defer { server.stop() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PipelineEndToEndTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskQueue = try FileDiskQueue(directoryURL: dir)
        let scrubber = Scrubber(downstream: DiskQueueEventSink(diskQueue: diskQueue))

        let (session, _) = APM.instrumentedSession(sink: scrubber, sessionManager: SessionManager())

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/user/628123456789/profile?msisdn=081234567890&page=2")!)
        request.setValue("Bearer super-secret-token-xyz", forHTTPHeaderField: "Authorization")
        request.setValue("session=abc123", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        session.dataTask(with: request).resume()

        // Poll disk (not the in-memory sink) — this must reflect what actually landed on disk.
        var stored: [Event] = []
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            stored = try diskQueue.peek(limit: 10)
            if !stored.isEmpty { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(stored.count == 1)
        guard let event = stored.first else { return }

        // 1) Query param VALUES redacted, names kept, path id-segment normalized.
        if case .string(let path)? = event.attrs["path"] {
            #expect(path == "/user/{id}/profile?msisdn=[redacted]&page=[redacted]")
        } else {
            Issue.record("expected a path attribute")
        }

        // 2) Authorization/Cookie never present; Content-Type (allowlisted) survives.
        if case .string(let headersJSON)? = event.attrs["req_headers"] {
            #expect(!headersJSON.contains("Authorization"))
            #expect(!headersJSON.contains("Cookie"))
            #expect(!headersJSON.contains("super-secret-token-xyz"))
            #expect(!headersJSON.contains("abc123"))
            #expect(headersJSON.contains("Content-Type"))
        } else {
            Issue.record("expected a req_headers attribute")
        }

        // 3) The disk-level proof: read the actual bytes written to the queue file. Neither
        // the raw phone number, the bearer token, nor the cookie value ever touched storage —
        // not just that the in-memory Event looks clean.
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(!files.isEmpty)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            #expect(!contents.contains("628123456789"))
            #expect(!contents.contains("081234567890"))
            #expect(!contents.contains("super-secret-token-xyz"))
            #expect(!contents.contains("abc123"))
            #expect(!contents.contains("Authorization"))
            #expect(!contents.contains("Cookie"))
        }
    }
}
