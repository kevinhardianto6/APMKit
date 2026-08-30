import Foundation

/// SDK self-health accounting (docs/02 §3.6, MOB-27) — "jumlah event tertulis vs terkirim vs
/// terbuang" (written vs sent vs dropped). This is the other half of `CONSTITUTION.md` rule
/// #1: internal failures are caught and fail silently into the host app, but they must not
/// vanish without a trace — this is where they're counted instead.
///
/// In-process introspection only, not a new wire event type — docs/01 §4 defines no
/// `self_health` event schema, so nothing here is sent to the backend; a host app that wants
/// to surface it (e.g. in a debug overlay, MOB-26) reads `snapshot()`.
///
/// Thread-safe: every call site that increments a counter runs on a different queue (disk
/// queue's own serial queue, `SyncEngine`'s work queue, ...), so this can't just be plain
/// `Int` properties.
public final class SelfHealthCounters {
    public static let shared = SelfHealthCounters()

    public struct Snapshot: Equatable {
        public var written: Int
        public var sent: Int
        public var dropped: Int
    }

    private let lock = NSLock()
    private var written = 0
    private var sent = 0
    private var dropped = 0

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

    /// An event never made it to the backend and never will: a disk write failure
    /// (`DiskQueueEventSink`), eviction under the disk-queue size cap (`FileDiskQueue`,
    /// MOB-06), or a batch the backend permanently rejected (docs/01 §7: 400 — "Catat sebagai
    /// metrik internal", i.e. the spec itself calls this out as a required self-health entry).
    public func recordDropped(_ count: Int = 1) {
        lock.lock(); dropped += count; lock.unlock()
    }

    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(written: written, sent: sent, dropped: dropped)
    }

    /// Test-only reset — production callers never need to zero this out mid-process.
    func reset() {
        lock.lock(); written = 0; sent = 0; dropped = 0; lock.unlock()
    }
}
