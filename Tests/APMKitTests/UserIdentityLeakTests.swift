import Testing
import Foundation
@testable import APMKit

/// The user_id leak concern (docs/01 §2.1, SEC-06): "the raw user_id must never leak into
/// breadcrumbs, logs, or any other field." Structurally, `user_id` never has the chance to —
/// `FileDiskQueue` only ever stores individual `Event`s; `Envelope` (the only place `user_id`
/// lives) is assembled purely in-memory by `EnvelopeFactory` at upload time, from a batch of
/// already-queued events. So `user_id` never touches the disk queue *at all*, which is a
/// stronger property than "it's scrubbed if present" — this test proves that stronger claim
/// directly, on real disk bytes, the same way `PipelineEndToEndTests` proved query/header
/// scrubbing.
@Suite("user_id leak-proofing — docs/01 §2.1, SEC-06")
struct UserIdentityLeakTests {
    @Test("a raw PII-shaped user_id never appears in any queued event, or in the actual queue-file bytes, across a real network request and a manual logError call")
    func userIdNeverLeaksIntoQueuedEventsOrDiskBytes() async throws {
        let suiteName = "UserIdentityLeakTests.\(UUID())"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let rawUserId = "081234567890" // phone-number-shaped, matches docs/02's own example PII
        UserIdentity.setUser(id: rawUserId, userDefaults: userDefaults)

        let server = MockHTTPServer { _, _ in .respond(status: 200) }
        try server.start()
        defer { server.stop() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("UserIdentityLeakTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskQueue = try FileDiskQueue(directoryURL: dir)
        let scrubber = Scrubber(downstream: DiskQueueEventSink(diskQueue: diskQueue))
        let sessionManager = SessionManager()

        // A real network event, unrelated to identity — proves setUser has no effect on
        // network capture's output.
        let (session, _) = APM.instrumentedSession(
            sink: scrubber, sessionManager: sessionManager,
            ingestEndpoint: .init(url: URL(string: "https://ingest.example.invalid/v1/ingest")!, appKey: "unused")
        )
        session.dataTask(with: URL(string: "http://127.0.0.1:\(server.port)/hello")!).resume()

        // A manual error report, with context — the most plausible accidental-leak vector
        // (a developer might reasonably expect user identity to show up in error context if
        // the SDK did something implicit/magic with it, which it must not).
        let reporter = ManualReporter(sink: scrubber, sessionManager: sessionManager)
        reporter.logError(NSError(domain: "TestDomain", code: 1), context: ["screen": "Checkout"])

        // Poll disk for both events to land.
        var stored: [Event] = []
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            stored = try diskQueue.peek(limit: 10)
            if stored.count >= 2 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(stored.count == 2)

        // 1) No queued Event's attrs or ctx contain the raw user_id, anywhere.
        for event in stored {
            for (key, value) in event.attrs {
                if case .string(let string) = value {
                    #expect(!string.contains(rawUserId), "user_id leaked into attrs[\(key)] of a \(event.type) event")
                }
            }
            #expect(event.ctx.screen?.contains(rawUserId) != true)
        }

        // 2) The disk-level proof: the raw user_id never appears in the actual queue-file
        // bytes — not just that the in-memory Events look clean.
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(!files.isEmpty)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            #expect(!contents.contains(rawUserId), "user_id leaked into queue file \(file.lastPathComponent)")
        }

        // 3) Confirm the raw value DOES reach the one legitimate place: the envelope built
        // from this batch at upload time. Not a leak — this is the whole point of user_id.
        let envelopeFactory = EnvelopeFactory(
            sessionManager: sessionManager,
            userId: { UserIdentity.currentUserId(userDefaults: userDefaults) }
        )
        let envelope = envelopeFactory.makeEnvelope(events: stored)
        #expect(envelope.userId == rawUserId)
    }
}
