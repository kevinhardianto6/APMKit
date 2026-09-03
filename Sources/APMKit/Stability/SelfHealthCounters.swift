import Foundation

/// SDK self-health accounting (docs/01 §2.3, docs/02 §3.6, MOB-27) — "jumlah event tertulis vs
/// terkirim vs terbuang" (written vs sent vs dropped), plus *why* dropped. This is the other
/// half of `CONSTITUTION.md` rule #1: internal failures are caught and fail silently into the
/// host app, but they must not vanish without a trace — this is where they're counted instead.
///
/// **Shipped in the envelope**, not just an in-process introspection point: `EnvelopeFactory`
/// reads `snapshot()` into `envelope.sdk.health` on every upload (docs/01 §2.3, added
/// 2026-09-02) — counters that never leave the device can't do the job this requirement exists
/// for, since it's precisely when the SDK is silently dropping data that nobody on the device
/// is watching for it. A host app that wants to surface this locally too (e.g. a debug
/// overlay, MOB-26) can still read `snapshot()` directly.
///
/// Thread-safe: every call site that increments a counter runs on a different queue (disk
/// queue's own serial queue, `SyncEngine`'s work queue, ...), so this can't just be plain
/// `Int`/`Dictionary` properties.
public final class SelfHealthCounters {
    public static let shared = SelfHealthCounters()

    public struct Snapshot: Equatable {
        public var written: Int
        public var sent: Int
        public var dropped: Int
        public var dropReasons: [String: Int]
    }

    private let lock = NSLock()
    private var written = 0
    private var sent = 0
    private var dropped = 0
    private var dropReasons: [String: Int] = [:]

    public init() {}

    /// One event durably landed on disk (`DiskQueueEventSink`, a successful `enqueue`).
    public func recordWritten(_ count: Int = 1) {
        lock.lock(); written += count; lock.unlock()
    }

    /// One or more events were accepted by the backend (`SyncEngine`, a 202 response) and
    /// removed from the disk queue.
    public func recordSent(_ count: Int) {
        lock.lock(); sent += count; lock.unlock()
    }

    /// An event never made it to the backend and never will. `reason` is open-ended by design
    /// (docs/01 §2.3) — current call sites use `write_failure` (`DiskQueueEventSink`: disk
    /// write failed), `queue_full` (`FileDiskQueue`: evicted under the size cap, MOB-06),
    /// `undecodable`/`decrypt_failure` (`FileDiskQueue.peek`: a poison file skipped rather than
    /// blocking every event behind it), and `rejected` (`SyncEngine`: the backend permanently
    /// rejected a batch, docs/01 §7 400 — "Catat sebagai metrik internal", the spec's own
    /// required entry). Defaults to `"unknown"` rather than making `reason` non-optional, so a
    /// future call site can't accidentally go uncounted by forgetting to pass one.
    public func recordDropped(_ count: Int = 1, reason: String = "unknown") {
        lock.lock()
        dropped += count
        dropReasons[reason, default: 0] += count
        lock.unlock()
    }

    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(written: written, sent: sent, dropped: dropped, dropReasons: dropReasons)
    }

    /// Test-only reset — production callers never need to zero this out mid-process.
    func reset() {
        lock.lock(); written = 0; sent = 0; dropped = 0; dropReasons = [:]; lock.unlock()
    }
}
