import Testing
import Foundation
@testable import APMKit

/// Returns scripted `UploadOutcome`s in order (falling back to `.transportFailure` once
/// exhausted) and records how many events were in each uploaded batch — enough to assert
/// on both the response-contract handling and the 413 split-and-retry behavior.
private final class ScriptedUploader: IngestUploading {
    private let lock = NSLock()
    private var outcomes: [UploadOutcome]
    private(set) var uploadedBatchSizes: [Int] = []

    init(outcomes: [UploadOutcome]) {
        self.outcomes = outcomes
    }

    func upload(envelope: Envelope, completion: @escaping (UploadOutcome) -> Void) {
        lock.lock()
        uploadedBatchSizes.append(envelope.events.count)
        let outcome = outcomes.isEmpty ? .transportFailure : outcomes.removeFirst()
        lock.unlock()
        completion(outcome)
    }

    func enqueue(_ outcome: UploadOutcome) {
        lock.lock(); outcomes.append(outcome); lock.unlock()
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return uploadedBatchSizes.count
    }
}

/// Mutable, test-controlled clock so pause/backoff windows can be asserted deterministically
/// without waiting on real wall-clock time.
private final class TestClock {
    var now: Date
    init(now: Date = Date()) { self.now = now }
    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@Suite("SyncEngine — docs/01 §7 response contract, docs/02 §3.3 MOB-07/08/09")
struct SyncEngineTests {
    private func makeDiskQueue() throws -> (FileDiskQueue, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SyncEngineTests-\(UUID().uuidString)")
        return (try FileDiskQueue(directoryURL: dir), dir)
    }

    private func makeEngine(
        diskQueue: DiskQueue, uploader: IngestUploading, clock: TestClock,
        configuration: SyncEngine.Configuration = .init(minBackoffSeconds: 1, maxBackoffSeconds: 100, pauseDurationSeconds: 60),
        selfHealth: SelfHealthCounters = SelfHealthCounters(),
        isEnabled: @escaping () -> Bool = { true }
    ) -> SyncEngine {
        SyncEngine(
            diskQueue: diskQueue, uploader: uploader,
            envelopeFactory: EnvelopeFactory(sessionManager: SessionManager()),
            configuration: configuration,
            clock: { clock.now },
            selfHealth: selfHealth,
            isEnabled: isEnabled
        )
    }

    private func trigger(_ engine: SyncEngine) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.triggerSync { continuation.resume() }
        }
    }

    @Test("202 accepted: batch is deleted from disk")
    func acceptedDeletesBatch() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        try diskQueue.enqueue(Event(type: "network", seq: 1))

        let uploader = ScriptedUploader(outcomes: [.accepted])
        let selfHealth = SelfHealthCounters()
        let engine = makeEngine(diskQueue: diskQueue, uploader: uploader, clock: TestClock(), selfHealth: selfHealth)
        await trigger(engine)

        #expect(try diskQueue.count() == 0)
        #expect(uploader.uploadedBatchSizes == [1])
        #expect(selfHealth.snapshot().sent == 1) // MOB-27
    }

    @Test("400 rejected: batch is dropped from disk, never retried")
    func rejectedDropsBatch() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        try diskQueue.enqueue(Event(type: "network", seq: 1))

        let uploader = ScriptedUploader(outcomes: [.rejected])
        let selfHealth = SelfHealthCounters()
        let engine = makeEngine(diskQueue: diskQueue, uploader: uploader, clock: TestClock(), selfHealth: selfHealth)
        await trigger(engine)

        #expect(try diskQueue.count() == 0)
        await trigger(engine) // nothing left to upload
        #expect(uploader.callCount == 1)
        #expect(selfHealth.snapshot().dropped == 1) // MOB-27, docs/01 §7: "Catat sebagai metrik internal"
    }

    @Test("MOB-21 kill switch: disabled means a sync cycle never uploads, even with data queued and a trigger fired")
    func killSwitchDisablesUpload() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        try diskQueue.enqueue(Event(type: "network", seq: 1))

        let uploader = ScriptedUploader(outcomes: [.accepted])
        let engine = makeEngine(diskQueue: diskQueue, uploader: uploader, clock: TestClock(), isEnabled: { false })
        await trigger(engine)

        #expect(uploader.callCount == 0)
        #expect(try diskQueue.count() == 1) // data stays queued, not lost — just not sent
    }

    @Test("401/403 unauthorized: data stays on disk, sending pauses for pauseDurationSeconds")
    func unauthorizedPausesAndKeepsData() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        try diskQueue.enqueue(Event(type: "network", seq: 1))

        let clock = TestClock()
        let uploader = ScriptedUploader(outcomes: [.unauthorized, .accepted])
        let engine = makeEngine(diskQueue: diskQueue, uploader: uploader, clock: clock, configuration: .init(minBackoffSeconds: 1, maxBackoffSeconds: 100, pauseDurationSeconds: 60))

        await trigger(engine)
        #expect(try diskQueue.count() == 1) // still queued
        #expect(uploader.callCount == 1)

        await trigger(engine) // still within the pause window
        #expect(uploader.callCount == 1) // uploader NOT called again

        clock.advance(by: 61)
        await trigger(engine)
        #expect(uploader.callCount == 2)
        #expect(try diskQueue.count() == 0)
    }

    @Test("413 payload too large: batch is split in half and retried")
    func payloadTooLargeSplitsBatch() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<10 { try diskQueue.enqueue(Event(type: "network", seq: i)) }

        let uploader = ScriptedUploader(outcomes: [.payloadTooLarge, .accepted, .accepted])
        let engine = makeEngine(
            diskQueue: diskQueue, uploader: uploader, clock: TestClock(),
            configuration: .init(maxEventsPerBatch: 10, minBackoffSeconds: 1, maxBackoffSeconds: 100, pauseDurationSeconds: 60)
        )
        await trigger(engine)

        #expect(uploader.uploadedBatchSizes == [10, 5, 5])
        #expect(try diskQueue.count() == 0)
    }

    @Test("429 rate limited: honors Retry-After when present")
    func rateLimitedHonorsRetryAfter() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        try diskQueue.enqueue(Event(type: "network", seq: 1))

        let clock = TestClock()
        let uploader = ScriptedUploader(outcomes: [.rateLimited(retryAfterSeconds: 10), .accepted])
        let engine = makeEngine(diskQueue: diskQueue, uploader: uploader, clock: clock)

        await trigger(engine)
        #expect(uploader.callCount == 1)

        clock.advance(by: 5) // still within the 10s Retry-After window
        await trigger(engine)
        #expect(uploader.callCount == 1)

        clock.advance(by: 6) // now past it
        await trigger(engine)
        #expect(uploader.callCount == 2)
        #expect(try diskQueue.count() == 0)
    }

    @Test("429 without Retry-After falls back to the current backoff")
    func rateLimitedWithoutRetryAfterUsesBackoff() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        try diskQueue.enqueue(Event(type: "network", seq: 1))

        let clock = TestClock()
        let uploader = ScriptedUploader(outcomes: [.rateLimited(retryAfterSeconds: nil), .accepted])
        let engine = makeEngine(diskQueue: diskQueue, uploader: uploader, clock: clock, configuration: .init(minBackoffSeconds: 5, maxBackoffSeconds: 100, pauseDurationSeconds: 60))

        await trigger(engine)
        #expect(uploader.callCount == 1)

        clock.advance(by: 6) // past the 5s min backoff
        await trigger(engine)
        #expect(uploader.callCount == 2)
    }

    @Test("5xx server error: exponential backoff doubles on repeated failures, data stays on disk")
    func serverErrorBacksOffExponentially() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        try diskQueue.enqueue(Event(type: "network", seq: 1))

        let clock = TestClock()
        let uploader = ScriptedUploader(outcomes: [.serverError, .serverError, .accepted])
        let engine = makeEngine(diskQueue: diskQueue, uploader: uploader, clock: clock, configuration: .init(minBackoffSeconds: 1, maxBackoffSeconds: 100, pauseDurationSeconds: 60))

        await trigger(engine) // backoff -> 1s, next backoff becomes 2s
        #expect(uploader.callCount == 1)
        #expect(try diskQueue.count() == 1)

        clock.advance(by: 1.5) // past the first 1s pause
        await trigger(engine) // second failure -> pause 2s, next backoff becomes 4s
        #expect(uploader.callCount == 2)

        clock.advance(by: 1) // NOT yet past the 2s pause from the second failure
        await trigger(engine)
        #expect(uploader.callCount == 2) // still paused, no new attempt

        clock.advance(by: 2) // now past it
        await trigger(engine)
        #expect(uploader.callCount == 3)
        #expect(try diskQueue.count() == 0)
    }

    @Test("transport failure (offline): data stays on disk, treated like a server error for backoff")
    func transportFailureBacksOffAndKeepsData() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        try diskQueue.enqueue(Event(type: "network", seq: 1))

        let uploader = ScriptedUploader(outcomes: [.transportFailure])
        let engine = makeEngine(diskQueue: diskQueue, uploader: uploader, clock: TestClock())
        await trigger(engine)

        #expect(try diskQueue.count() == 1)
        #expect(uploader.callCount == 1)
    }

    @Test("buffers offline, flushes on reconnect: connectivityRestored() drains the backlog once the uploader succeeds")
    func buffersOfflineFlushesOnReconnect() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<3 { try diskQueue.enqueue(Event(type: "network", seq: i)) }

        let clock = TestClock()
        // "offline": the first attempt fails at the transport level.
        let uploader = ScriptedUploader(outcomes: [.transportFailure])
        let engine = makeEngine(diskQueue: diskQueue, uploader: uploader, clock: clock)

        await trigger(engine)
        #expect(try diskQueue.count() == 3) // nothing lost, all still buffered
        #expect(uploader.callCount == 1)

        // "reconnect": move past the backoff window this same engine is now under, queue up
        // a success, and use the actual reconnect trigger (not `triggerSync` directly).
        clock.advance(by: 5)
        uploader.enqueue(.accepted)
        engine.connectivityRestored()

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, ((try? diskQueue.count()) ?? 0) != 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(try diskQueue.count() == 0)
        // One 3-event batch uploaded successfully on reconnect (default maxEventsPerBatch
        // comfortably covers all 3 in a single call).
        #expect(uploader.uploadedBatchSizes == [3, 3])
    }

    @Test("appDidEnterBackground() also triggers a sync cycle")
    func backgroundTransitionTriggersSync() async throws {
        let (diskQueue, dir) = try makeDiskQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        try diskQueue.enqueue(Event(type: "network", seq: 1))

        let uploader = ScriptedUploader(outcomes: [.accepted])
        let engine = makeEngine(diskQueue: diskQueue, uploader: uploader, clock: TestClock())
        engine.appDidEnterBackground()

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, ((try? diskQueue.count()) ?? 0) != 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(try diskQueue.count() == 0)
    }

    @Test("MOB-09 anti-loop: IngestClient's default session has no delegate")
    func uploaderSessionHasNoDelegate() {
        let client = IngestClient(endpoint: .init(url: URL(string: "https://ingest.example.com/v1/ingest")!, appKey: "test-key"))
        #expect(client.session.delegate == nil)
    }
}
