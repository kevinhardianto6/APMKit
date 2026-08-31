import Testing
import Foundation
@testable import APMKit

/// `APM.start`'s fallback when `FileDiskQueue.init` throws (`CONSTITUTION.md` rule #1: never
/// propagate that into the host). Same `DiskQueue` contract `FileDiskQueue`'s own tests already
/// prove against the real filesystem — this suite proves the in-memory implementation honors
/// the identical contract, since `SyncEngine` treats both interchangeably through the protocol.
@Suite("EphemeralInMemoryDiskQueue — APM.start's never-throw fallback")
struct EphemeralInMemoryDiskQueueTests {
    private func makeEvent(seq: Int = 1) -> Event {
        Event(type: "test", seq: seq, attrs: [:])
    }

    @Test("enqueue then peek returns events in FIFO order")
    func enqueueThenPeekReturnsFIFOOrder() throws {
        let queue = EphemeralInMemoryDiskQueue()
        let first = makeEvent(seq: 1)
        let second = makeEvent(seq: 2)

        try queue.enqueue(first)
        try queue.enqueue(second)

        let events = try queue.peek(limit: 10)
        #expect(events.map(\.eventId) == [first.eventId, second.eventId])
    }

    @Test("remove deletes only the given event ids, preserving order of the rest")
    func removeDeletesOnlyGivenIds() throws {
        let queue = EphemeralInMemoryDiskQueue()
        let a = makeEvent(seq: 1)
        let b = makeEvent(seq: 2)
        let c = makeEvent(seq: 3)
        try queue.enqueue(a)
        try queue.enqueue(b)
        try queue.enqueue(c)

        try queue.remove(eventIds: [b.eventId])

        let remaining = try queue.peek(limit: 10)
        #expect(remaining.map(\.eventId) == [a.eventId, c.eventId])
    }

    @Test("count() and sizeInBytes() reflect what's actually queued")
    func countAndSizeReflectQueuedEvents() throws {
        let queue = EphemeralInMemoryDiskQueue()
        #expect(try queue.count() == 0)
        let emptySize = try queue.sizeInBytes()

        try queue.enqueue(makeEvent())

        #expect(try queue.count() == 1)
        #expect(try queue.sizeInBytes() > emptySize)
    }

    @Test("peek respects the limit")
    func peekRespectsLimit() throws {
        let queue = EphemeralInMemoryDiskQueue()
        for i in 1...5 { try queue.enqueue(makeEvent(seq: i)) }

        #expect(try queue.peek(limit: 2).count == 2)
    }
}
