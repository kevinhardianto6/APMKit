import Testing
import Foundation
@testable import APMKit

@Suite("FileDiskQueue — docs/02 §3.2, MOB-04/05/06")
struct FileDiskQueueTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FileDiskQueueTests-\(UUID().uuidString)")
    }

    @Test("enqueue then peek returns events in FIFO order")
    func enqueueThenPeekIsFIFO() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let queue = try FileDiskQueue(directoryURL: dir)

        try queue.enqueue(Event(type: "a", seq: 1))
        try queue.enqueue(Event(type: "b", seq: 2))
        try queue.enqueue(Event(type: "c", seq: 3))

        let peeked = try queue.peek(limit: 10)
        #expect(peeked.map(\.type) == ["a", "b", "c"])
        #expect(try queue.count() == 3)
    }

    @Test("survives a simulated process restart: new instance over the same directory sees prior events")
    func survivesSimulatedRestart() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            let queue = try FileDiskQueue(directoryURL: dir)
            try queue.enqueue(Event(type: "network", seq: 1))
            try queue.enqueue(Event(type: "network_failure", seq: 2))
            // `queue` goes out of scope here — simulates process death; nothing is flushed
            // on deinit because enqueue() already durably wrote each event synchronously.
        }

        let reopened = try FileDiskQueue(directoryURL: dir)
        let recovered = try reopened.peek(limit: 10)
        #expect(recovered.map(\.type) == ["network", "network_failure"])
    }

    @Test("a fresh instance after restart continues the sequence instead of colliding")
    func sequenceRecoveryAvoidsCollisionAfterRestart() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            let queue = try FileDiskQueue(directoryURL: dir)
            for i in 0..<3 { try queue.enqueue(Event(type: "e\(i)", seq: i)) }
        }

        let reopened = try FileDiskQueue(directoryURL: dir)
        try reopened.enqueue(Event(type: "after-restart", seq: 99))

        let all = try reopened.peek(limit: 10)
        #expect(all.count == 4)
        #expect(all.last?.type == "after-restart")
    }

    @Test("remove deletes only the given event ids, preserving order of the rest")
    func removeDeletesOnlyGivenIds() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let queue = try FileDiskQueue(directoryURL: dir)

        let a = Event(type: "a", seq: 1)
        let b = Event(type: "b", seq: 2)
        let c = Event(type: "c", seq: 3)
        try queue.enqueue(a)
        try queue.enqueue(b)
        try queue.enqueue(c)

        try queue.remove(eventIds: [b.eventId])

        let remaining = try queue.peek(limit: 10)
        #expect(remaining.map(\.type) == ["a", "c"])
        #expect(try queue.count() == 2)
    }

    @Test("FIFO-evicts oldest events when the event-count cap is exceeded")
    func evictsOldestWhenCountCapExceeded() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let selfHealth = SelfHealthCounters()
        let queue = try FileDiskQueue(
            directoryURL: dir,
            configuration: .init(maxBytes: .max, maxEventCount: 3),
            selfHealth: selfHealth
        )

        for i in 0..<5 { try queue.enqueue(Event(type: "e\(i)", seq: i)) }

        let remaining = try queue.peek(limit: 10)
        #expect(remaining.count == 3)
        #expect(remaining.map(\.type) == ["e2", "e3", "e4"])
        // MOB-27: the 2 evicted events were never sent — must be counted as dropped.
        #expect(selfHealth.snapshot().dropped == 2)
    }

    @Test("FIFO-evicts oldest events when the byte-size cap is exceeded")
    func evictsOldestWhenByteCapExceeded() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Each encoded event is a small but non-trivial number of bytes; force eviction
        // with a byte cap sized to only fit ~2 events, well under the unbounded count cap.
        let probe = try JSONEncoder().encode(Event(type: "probe", seq: 0, attrs: ["k": "some-attribute-value"]))
        let capBytes = probe.count * 2 + 10

        let queue = try FileDiskQueue(
            directoryURL: dir,
            configuration: .init(maxBytes: capBytes, maxEventCount: .max)
        )

        for i in 0..<5 {
            try queue.enqueue(Event(type: "e\(i)", seq: i, attrs: ["k": "some-attribute-value"]))
        }

        let remaining = try queue.peek(limit: 10)
        #expect(remaining.count < 5)
        #expect(try queue.sizeInBytes() <= capBytes)
        #expect(remaining.last?.type == "e4")
    }

    @Test("a stray non-.json artifact in the queue directory (simulating a torn write) is never surfaced")
    func strayArtifactIsIgnored() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let queue = try FileDiskQueue(directoryURL: dir)

        try queue.enqueue(Event(type: "real", seq: 1))
        // Data.write(options: .atomic) never leaves a torn .json file behind — but its
        // *temporary* file (before the atomic rename lands) would carry a different
        // extension, which is exactly what a kill mid-write would leave on disk.
        try Data("not a real event".utf8).write(to: dir.appendingPathComponent("leftover.tmp"))

        let recovered = try queue.peek(limit: 10)
        #expect(recovered.map(\.type) == ["real"])
        #expect(try queue.count() == 1)
    }

    @Test("sizeInBytes reflects actual on-disk usage and drops after eviction/removal")
    func sizeInBytesTracksUsage() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let queue = try FileDiskQueue(directoryURL: dir)

        #expect(try queue.sizeInBytes() == 0)
        let event = Event(type: "a", seq: 1)
        try queue.enqueue(event)
        #expect(try queue.sizeInBytes() > 0)

        try queue.remove(eventIds: [event.eventId])
        #expect(try queue.sizeInBytes() == 0)
    }
}
