import Testing
import Foundation
@testable import APMKit

/// docs/02 §6.1 explicitly names breadcrumbs as a PII leak path (`logError(e, ["phone":
/// user.phone])`-style mistakes) — feat-004 proved the `Scrubber` handles a synthetic
/// breadcrumb-typed `Event` correctly, ahead of a real producer existing. This proves it for
/// the REAL producer: a phone number a developer puts in a real `APM.breadcrumb(...)` call,
/// attached to a real `logError`, through the real `Scrubber` → `FileDiskQueue` pipeline —
/// checked against actual queue-file bytes, not just the in-memory `Event`.
@Suite("Breadcrumb PII leak-proofing — docs/02 §6.1")
struct BreadcrumbLeakTests {
    private func string(_ event: Event, _ key: String) -> String? {
        if case .string(let value)? = event.attrs[key] { return value }
        return nil
    }

    @Test("a phone number in a breadcrumb message is redacted before it ever reaches disk")
    func phoneNumberInBreadcrumbNeverReachesDiskUnredacted() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BreadcrumbLeakTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskQueue = try FileDiskQueue(directoryURL: dir)
        let scrubber = Scrubber(downstream: DiskQueueEventSink(diskQueue: diskQueue))

        let rawPhoneNumber = "081234567890"
        let buffer = BreadcrumbRingBuffer(capacity: 100)
        // The exact mistake docs/02 §6.1 warns about: a developer putting PII straight into
        // a breadcrumb message, expecting the SDK — not their own discipline — to catch it.
        buffer.add(Breadcrumb(category: .userAction, message: "user entered phone \(rawPhoneNumber) at checkout"))
        buffer.add(Breadcrumb(category: .navigation, message: "CheckoutScreen"))

        let reporter = ManualReporter(sink: scrubber, sessionManager: SessionManager(), breadcrumbs: buffer)
        reporter.logError(NSError(domain: "TestDomain", code: 1))

        let stored = try diskQueue.peek(limit: 10)
        #expect(stored.count == 1)
        let breadcrumbsJSON = try #require(string(stored[0], "breadcrumbs"))

        #expect(!breadcrumbsJSON.contains(rawPhoneNumber))
        #expect(breadcrumbsJSON.contains("[redacted]"))

        // Disk-level proof: the raw phone number never touched the actual queue-file bytes.
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(!files.isEmpty)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            #expect(!contents.contains(rawPhoneNumber), "phone number leaked into queue file \(file.lastPathComponent)")
        }
    }
}
