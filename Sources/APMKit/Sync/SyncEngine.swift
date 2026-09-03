import Foundation

/// Batched upload orchestration (docs/02 §3.3, MOB-07/08/09). Owns the exact response
/// contract from docs/01 §7 and the three required triggers (MOB-08): a periodic timer,
/// background transition, and connectivity restore — callers invoke `appDidEnterBackground()`
/// / `connectivityRestored()` from wherever they observe those (UIKit notifications,
/// `NWPathMonitor`, ...); `SyncEngine` itself stays platform-agnostic.
///
/// All work happens on a private serial queue, off the main thread (perf budget, docs/02 §5).
/// `IngestUploading.upload` is bridged back to synchronous flow with a semaphore — safe here
/// because this queue exists solely to run sync cycles sequentially; it is never the main
/// queue and nothing else waits on it.
public final class SyncEngine {
    public struct Configuration {
        /// docs/01 §7: "maksimum 200 event per request" — the only client-*enforced* cap.
        /// The other stated limit ("maksimum 1 MB terkompresi") is deliberately NOT
        /// pre-checked here: estimating compressed size before compressing is inaccurate,
        /// and actually compressing just to measure would duplicate `IngestClient`'s work.
        /// Docs/01 §7 already defines the mechanism for this — a `413` response — and
        /// `SyncEngine` already halves the batch and retries on exactly that (see
        /// `.payloadTooLarge` handling). Server-driven is the source of truth for the real
        /// limit; client-side pre-computation would just be a guess at it.
        public var maxEventsPerBatch: Int
        public var uploadIntervalSeconds: TimeInterval
        public var minBackoffSeconds: TimeInterval
        public var maxBackoffSeconds: TimeInterval
        public var pauseDurationSeconds: TimeInterval

        public init(
            maxEventsPerBatch: Int = 200,
            uploadIntervalSeconds: TimeInterval = 30,
            minBackoffSeconds: TimeInterval = 30,
            maxBackoffSeconds: TimeInterval = 30 * 60,
            pauseDurationSeconds: TimeInterval = 24 * 60 * 60
        ) {
            self.maxEventsPerBatch = maxEventsPerBatch
            self.uploadIntervalSeconds = uploadIntervalSeconds
            self.minBackoffSeconds = minBackoffSeconds
            self.maxBackoffSeconds = maxBackoffSeconds
            self.pauseDurationSeconds = pauseDurationSeconds
        }
    }

    private let diskQueue: DiskQueue
    private let uploader: IngestUploading
    private let envelopeFactory: EnvelopeFactory
    private let configuration: Configuration
    private let clock: () -> Date
    private let selfHealth: SelfHealthCounters
    /// MOB-21 kill switch (feat-010): checked at the top of every sync cycle. `nil`/default
    /// means "always enabled" — existing callers that don't pass a remote-config-backed
    /// closure see no behavior change.
    private let isEnabled: () -> Bool

    private let workQueue = DispatchQueue(label: "kit.apm.syncengine")
    private var timer: DispatchSourceTimer?
    private var pausedUntil: Date?
    private var currentBackoff: TimeInterval
    private var isSyncing = false

    public init(
        diskQueue: DiskQueue,
        uploader: IngestUploading,
        envelopeFactory: EnvelopeFactory,
        configuration: Configuration = Configuration(),
        clock: @escaping () -> Date = Date.init,
        selfHealth: SelfHealthCounters = .shared,
        isEnabled: @escaping () -> Bool = { true }
    ) {
        self.diskQueue = diskQueue
        self.uploader = uploader
        self.envelopeFactory = envelopeFactory
        self.configuration = configuration
        self.clock = clock
        self.selfHealth = selfHealth
        self.isEnabled = isEnabled
        self.currentBackoff = configuration.minBackoffSeconds
    }

    // MARK: - Lifecycle / triggers (MOB-08)

    public func start() {
        workQueue.async { [weak self] in self?.scheduleTimer() }
    }

    public func stop() {
        workQueue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    public func appDidEnterBackground() { triggerSync() }
    public func connectivityRestored() { triggerSync() }

    /// Runs one sync cycle. Exposed publicly (not just via the internal timer) so tests and
    /// the periodic timer share the exact same code path — `completion` fires after the
    /// cycle finishes, purely so tests can await it deterministically instead of polling.
    public func triggerSync(completion: (() -> Void)? = nil) {
        workQueue.async { [weak self] in
            self?.performSyncCycle()
            completion?()
        }
    }

    private func scheduleTimer() {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: workQueue)
        source.schedule(deadline: .now() + configuration.uploadIntervalSeconds, repeating: configuration.uploadIntervalSeconds)
        source.setEventHandler { [weak self] in self?.performSyncCycle() }
        source.resume()
        timer = source
    }

    // MARK: - Sync cycle (must run on workQueue)

    private func performSyncCycle() {
        guard !isSyncing else { return }
        guard isEnabled() else { return } // MOB-21: kill switch — data stays queued, never uploaded
        if let pausedUntil, clock() < pausedUntil { return }
        isSyncing = true
        defer { isSyncing = false }
        drainQueue(limit: configuration.maxEventsPerBatch)
    }

    /// Keeps uploading batches while there's data and nothing has told it to stop (a pause
    /// was set, or the disk queue is empty) — this is what makes "flushes on reconnect"
    /// actually drain a backlog in one cycle instead of one batch per timer tick.
    private func drainQueue(limit: Int) {
        guard limit > 0 else { return }
        guard let batch = try? diskQueue.peek(limit: limit), !batch.isEmpty else { return }

        let envelope = envelopeFactory.makeEnvelope(events: batch)
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: UploadOutcome = .transportFailure
        uploader.upload(envelope: envelope) { result in
            outcome = result
            semaphore.signal()
        }
        semaphore.wait()

        handle(outcome: outcome, batch: batch, limit: limit)
    }

    private func handle(outcome: UploadOutcome, batch: [Event], limit: Int) {
        let ids = Set(batch.map(\.eventId))

        switch outcome {
        case .accepted:
            try? diskQueue.remove(eventIds: ids)
            selfHealth.recordSent(ids.count)
            currentBackoff = configuration.minBackoffSeconds
            drainQueue(limit: limit) // more may remain — keep going within this cycle

        case .rejected:
            // docs/01 §7: drop the batch, never retry — a malformed/unrecognized payload
            // will never succeed no matter how many times it's resent. The spec explicitly
            // calls this out as a required internal metric ("Catat sebagai metrik internal").
            try? diskQueue.remove(eventIds: ids)
            selfHealth.recordDropped(ids.count, reason: "rejected")
            currentBackoff = configuration.minBackoffSeconds

        case .unauthorized:
            pausedUntil = clock().addingTimeInterval(configuration.pauseDurationSeconds)
            // data stays on disk; stop this cycle

        case .payloadTooLarge:
            guard limit > 1 else {
                // Can't split a single event any further. Leave it on disk rather than
                // dropping it — back off so this doesn't spin in a tight retry loop.
                pausedUntil = clock().addingTimeInterval(currentBackoff)
                currentBackoff = min(currentBackoff * 2, configuration.maxBackoffSeconds)
                return
            }
            drainQueue(limit: max(1, limit / 2))

        case .rateLimited(let retryAfterSeconds):
            pausedUntil = clock().addingTimeInterval(retryAfterSeconds ?? currentBackoff)

        case .serverError, .transportFailure:
            pausedUntil = clock().addingTimeInterval(currentBackoff)
            currentBackoff = min(currentBackoff * 2, configuration.maxBackoffSeconds)
        }
    }
}
