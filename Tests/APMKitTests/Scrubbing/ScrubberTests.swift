import Testing
import Foundation
@testable import APMKit

@Suite("Scrubber — docs/02 §6.1, CONSTITUTION.md Capture → Scrub → Disk")
struct ScrubberTests {
    private func string(_ event: Event, _ key: String) -> String? {
        if case .string(let value)? = event.attrs[key] { return value }
        return nil
    }

    @Test("removes a phone number from a network event's path")
    func removesPhoneFromPath() {
        let sink = CollectingEventSink()
        let scrubber = Scrubber(downstream: sink)

        let event = Event(
            type: "network",
            seq: 1,
            attrs: ["host": .string("api.example.com"), "path": .string("/user/628123456789/profile")]
        )
        scrubber.receive(event)

        #expect(sink.events.count == 1)
        #expect(string(sink.events[0], "path") == "/user/{id}/profile")
    }

    @Test("removes a phone number from an error-like event's message attribute")
    func removesPhoneFromErrorMessage() {
        // No dedicated `error` event producer exists yet (feat-006) — this proves the
        // scrubbing pipeline is generic across event types, not network-specific, ahead of
        // that feature landing.
        let sink = CollectingEventSink()
        let scrubber = Scrubber(downstream: sink)

        let event = Event(
            type: "error",
            seq: 1,
            attrs: ["message": .string("Gagal mengirim OTP ke 081234567890")]
        )
        scrubber.receive(event)

        #expect(sink.events.count == 1)
        #expect(string(sink.events[0], "message")?.contains("0812") == false)
        #expect(string(sink.events[0], "message") == "Gagal mengirim OTP ke [redacted]")
    }

    @Test("removes a phone number from a breadcrumb-like event's message attribute")
    func removesPhoneFromBreadcrumbMessage() {
        // No dedicated `breadcrumb` event producer exists yet (feat-007) — same generic-
        // pipeline proof as the error case above.
        let sink = CollectingEventSink()
        let scrubber = Scrubber(downstream: sink)

        let event = Event(
            type: "breadcrumb",
            seq: 1,
            attrs: ["message": .string("logError(e, [\"phone\": \"081234567890\"])")]
        )
        scrubber.receive(event)

        #expect(sink.events.count == 1)
        #expect(string(sink.events[0], "message") == "logError(e, [\"phone\": \"[redacted]\"])")
    }

    @Test("removes a phone number from screen names (docs/02 example: OTPVerification-0812xxxxxxx)")
    func removesPhoneFromScreenName() {
        let sink = CollectingEventSink()
        let scrubber = Scrubber(downstream: sink)

        let event = Event(
            type: "network",
            seq: 1,
            attrs: ["host": .string("api.example.com"), "path": .string("/ok")],
            ctx: EventContext(screen: "OTPVerification-081234567890")
        )
        scrubber.receive(event)

        #expect(sink.events.count == 1)
        #expect(sink.events[0].ctx.screen == "OTPVerification-[redacted]")
    }

    @Test("does not touch attrs/ctx that contain no PII")
    func leavesCleanEventUntouched() {
        let sink = CollectingEventSink()
        let scrubber = Scrubber(downstream: sink)

        let event = Event(
            type: "network",
            seq: 1,
            attrs: ["host": .string("api.example.com"), "path": .string("/health"), "status_code": .int(200)],
            ctx: EventContext(screen: "HomeViewController", appState: "foreground")
        )
        scrubber.receive(event)

        #expect(sink.events.count == 1)
        let scrubbed = sink.events[0]
        #expect(string(scrubbed, "host") == "api.example.com")
        #expect(string(scrubbed, "path") == "/health")
        #expect(scrubbed.ctx.screen == "HomeViewController")
    }

    @Test("end-to-end: Scrubber in front of a real FileDiskQueue never persists a phone number to disk")
    func endToEndScrubbedBeforeDiskWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ScrubberTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskQueue = try FileDiskQueue(directoryURL: dir, encryption: nil) // feat-014: reads raw plaintext bytes below to test the SEC-01/05/06 scrubbing layer, not encryption
        let diskSink = DiskQueueEventSink(diskQueue: diskQueue)
        let scrubber = Scrubber(downstream: diskSink)

        let event = Event(
            type: "network_failure",
            seq: 1,
            attrs: [
                "host": .string("api.example.com"),
                "path": .string("/user/628123456789/profile"),
                "method": .string("GET"),
                "failure_category": .string("timeout"),
                "duration_ms": .int(500)
            ]
        )
        scrubber.receive(event)

        let stored = try diskQueue.peek(limit: 10)
        #expect(stored.count == 1)
        #expect(string(stored[0], "path") == "/user/{id}/profile")

        // Prove it's not just the in-memory Event that's clean — the actual bytes on disk
        // never contained the raw phone number, since scrubbing ran before the write.
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            #expect(!contents.contains("628123456789"))
        }
    }
}
