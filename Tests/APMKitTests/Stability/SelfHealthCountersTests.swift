import Testing
import Foundation
@testable import APMKit

private struct ThrowingDiskQueue: DiskQueue {
    struct Failure: Error {}
    func enqueue(_ event: Event) throws { throw Failure() }
    func peek(limit: Int) throws -> [Event] { [] }
    func remove(eventIds: Set<String>) throws {}
    func count() throws -> Int { 0 }
    func sizeInBytes() throws -> Int { 0 }
}

@Suite("SelfHealthCounters — docs/02 §3.6 MOB-27")
struct SelfHealthCountersTests {
    @Test("written/sent/dropped accumulate independently and are readable via snapshot()")
    func countersAccumulate() {
        let counters = SelfHealthCounters()
        counters.recordWritten()
        counters.recordWritten(2)
        counters.recordSent(5)
        counters.recordDropped()

        let snapshot = counters.snapshot()
        #expect(snapshot.written == 3)
        #expect(snapshot.sent == 5)
        #expect(snapshot.dropped == 1)
    }

    @Test("concurrent increments from multiple queues don't lose updates")
    func threadSafeUnderConcurrentIncrement() async {
        let counters = SelfHealthCounters()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<500 {
                group.addTask { counters.recordWritten() }
            }
        }
        #expect(counters.snapshot().written == 500)
    }

    @Test("drop_reasons (docs/01 §2.3) accumulates independently per reason, and reasons never seen keep dropped's total correct")
    func dropReasonsAccumulatePerReason() {
        let counters = SelfHealthCounters()
        counters.recordDropped(reason: "queue_full")
        counters.recordDropped(3, reason: "queue_full")
        counters.recordDropped(reason: "rejected")

        let snapshot = counters.snapshot()
        #expect(snapshot.dropped == 5)
        #expect(snapshot.dropReasons["queue_full"] == 4)
        #expect(snapshot.dropReasons["rejected"] == 1)
        #expect(snapshot.dropReasons.count == 2)
    }

    @Test("recordDropped with no reason argument still counts, under \"unknown\" — a future call site can't go uncounted by forgetting to pass one")
    func recordDroppedDefaultsToUnknownReason() {
        let counters = SelfHealthCounters()
        counters.recordDropped()

        let snapshot = counters.snapshot()
        #expect(snapshot.dropped == 1)
        #expect(snapshot.dropReasons["unknown"] == 1)
    }
}

@Suite("DiskQueueEventSink — MOB-27 write/drop accounting")
struct DiskQueueEventSinkSelfHealthTests {
    @Test("a successful enqueue counts as written")
    func successfulEnqueueCountsAsWritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DiskQueueEventSinkTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let queue = try FileDiskQueue(directoryURL: dir)
        let selfHealth = SelfHealthCounters()
        let sink = DiskQueueEventSink(diskQueue: queue, selfHealth: selfHealth)

        sink.receive(Event(type: "network", seq: 1))

        #expect(selfHealth.snapshot().written == 1)
        #expect(selfHealth.snapshot().dropped == 0)
    }

    @Test("a disk-queue failure is swallowed (CONSTITUTION.md rule #1) but counted as dropped, not silently lost")
    func failedEnqueueCountsAsDropped() {
        let selfHealth = SelfHealthCounters()
        let sink = DiskQueueEventSink(diskQueue: ThrowingDiskQueue(), selfHealth: selfHealth)

        sink.receive(Event(type: "network", seq: 1)) // must not throw

        #expect(selfHealth.snapshot().dropped == 1)
        #expect(selfHealth.snapshot().written == 0)
        #expect(selfHealth.snapshot().dropReasons["write_failure"] == 1)
    }
}
