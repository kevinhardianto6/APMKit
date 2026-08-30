import Testing
import Foundation
@testable import APMKit

/// Wraps a real `DiskQueue` and adds artificial latency to `peek` — standing in for a slow
/// disk (e.g. a large queue, a busy device) so the tests below can prove `SyncEngine`'s
/// automatic entry points don't block the calling thread waiting for it.
private final class SlowDiskQueue: DiskQueue {
    private let wrapped: DiskQueue
    private let delay: TimeInterval

    init(wrapping wrapped: DiskQueue, delay: TimeInterval) {
        self.wrapped = wrapped
        self.delay = delay
    }

    func enqueue(_ event: Event) throws { try wrapped.enqueue(event) }
    func peek(limit: Int) throws -> [Event] {
        Thread.sleep(forTimeInterval: delay)
        return try wrapped.peek(limit: limit)
    }
    func remove(eventIds: Set<String>) throws { try wrapped.remove(eventIds: eventIds) }
    func count() throws -> Int { try wrapped.count() }
    func sizeInBytes() throws -> Int { try wrapped.sizeInBytes() }
}

/// Stands in for a slow network — the upload doesn't complete until `delay` has elapsed.
private final class SlowUploader: IngestUploading {
    private let delay: TimeInterval
    init(delay: TimeInterval) { self.delay = delay }

    func upload(envelope: Envelope, completion: @escaping (UploadOutcome) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            completion(.accepted)
        }
    }
}

/// docs/02 §5 (feat-012): "main thread: nol operasi I/O blocking." This is a structural,
/// dynamic proof for the part of that budget this repo can actually assert without a real
/// device — `SyncEngine`'s automatic triggers (`appDidEnterBackground`, `connectivityRestored`)
/// are the SDK's own internal entry points that touch disk and network; this proves they
/// return to the caller immediately regardless of how slow the underlying I/O is, because the
/// real work happens on `SyncEngine`'s own private `workQueue`, not synchronously on whatever
/// thread called them.
///
/// **What this does NOT cover, on purpose — see FEATURES.md's feat-012 entry:** the manual
/// APIs (`APM.logError`, `APM.breadcrumb`, `APM.recordFirstFrame`) are synchronous by design
/// (`ManualReporter`'s own doc comment: "whatever thread the host calls them on") — if a host
/// app calls one of those from its own main thread, that call *does* block on disk I/O. This
/// is pre-existing, documented behavior this feature doesn't change or paper over; it's a
/// caller-responsibility case, not a gap in the SDK's own automatic entry points.
@Suite("Main-thread I/O — structural proof, docs/02 §5, feat-012")
struct MainThreadIOStructuralTests {
    private let slow: TimeInterval = 0.5
    /// Generous relative to `slow` (0.5s) — this asserts "near-instant," not a specific
    /// number, so it isn't flaky under CI load while still failing hard if the call ever
    /// actually waits on the slow disk/network stand-ins.
    private let mustReturnWithin: TimeInterval = 0.05

    private func makeEngine() throws -> (engine: SyncEngine, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MainThreadIOStructuralTests-\(UUID().uuidString)")
        let real = try FileDiskQueue(directoryURL: dir)
        try real.enqueue(Event(type: "network", seq: 1))
        let slowQueue = SlowDiskQueue(wrapping: real, delay: slow)
        let engine = SyncEngine(
            diskQueue: slowQueue,
            uploader: SlowUploader(delay: slow),
            envelopeFactory: EnvelopeFactory(sessionManager: SessionManager())
        )
        return (engine, dir)
    }

    @Test("appDidEnterBackground() returns immediately even with a slow disk and a slow uploader behind it")
    func appDidEnterBackgroundDoesNotBlock() throws {
        let (engine, dir) = try makeEngine()
        defer { try? FileManager.default.removeItem(at: dir) }

        let start = Date()
        engine.appDidEnterBackground()
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < mustReturnWithin)
    }

    @Test("connectivityRestored() returns immediately even with a slow disk and a slow uploader behind it")
    func connectivityRestoredDoesNotBlock() throws {
        let (engine, dir) = try makeEngine()
        defer { try? FileManager.default.removeItem(at: dir) }

        let start = Date()
        engine.connectivityRestored()
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < mustReturnWithin)
    }

    @Test("APM.instrumentedSession() uses delegateQueue: nil, so network capture callbacks run on their own private queue, never OperationQueue.main")
    func instrumentedSessionDoesNotUseMainQueueForCallbacks() {
        // `nil` tells URLSession to create its own private serial operation queue for
        // delegate callbacks — the one line in APMKit.swift that keeps NetworkCaptureDelegate
        // off the main thread. `OperationQueue.main` is a singleton, so identity comparison
        // against it is the meaningful check (its `.underlyingQueue` isn't reliably set either
        // way, so comparing that would be a false signal). Asserted directly here so a future
        // edit that accidentally passes `.main` fails a test immediately rather than only
        // showing up as jank.
        let sink = CollectingEventSink()
        let (session, _) = APM.instrumentedSession(
            sink: sink,
            sessionManager: SessionManager(),
            ingestEndpoint: IngestEndpoint(url: URL(string: "https://example.com/v1/ingest")!, appKey: "key")
        )
        #expect(session.delegateQueue !== OperationQueue.main)
    }
}
