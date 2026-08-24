import Foundation

/// Local-first event persistence — docs/02 §3.2 (MOB-04/05/06). Capture → Scrub → **Disk** →
/// Sync (`CONSTITUTION.md`): every event is durably on disk before any network call is made,
/// and stays there until the sync engine (feat-005) deletes it after a 2xx response.
///
/// Behind a protocol so the sync engine can be tested against an in-memory fake without
/// touching the filesystem, and so the on-disk format can change without touching callers.
public protocol DiskQueue {
    /// Durably appends one event. Blocks the calling thread until the write has landed on
    /// disk (or throws) — callers MUST invoke this off the main thread (perf budget,
    /// docs/02 §5), and must not proceed to any network call until this returns.
    func enqueue(_ event: Event) throws

    /// The oldest `limit` events currently queued, oldest-first (FIFO order).
    func peek(limit: Int) throws -> [Event]

    /// Removes exactly the given event ids. Call only after a successful (2xx) upload ack —
    /// deleting earlier breaks the at-least-once delivery guarantee (docs/01 §2 intro).
    func remove(eventIds: Set<String>) throws

    /// Number of events currently queued.
    func count() throws -> Int

    /// Total on-disk size of the queue, in bytes.
    func sizeInBytes() throws -> Int
}
