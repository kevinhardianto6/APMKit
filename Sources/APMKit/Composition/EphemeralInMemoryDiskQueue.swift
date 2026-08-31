import Foundation

/// `CONSTITUTION.md` rule #1: `APM.start` must never throw into the host app, but
/// `FileDiskQueue.init` does throw (directory creation can fail — a full disk, a sandboxed
/// container with an unwritable Caches directory, ...). This is the fallback for exactly that
/// case: an in-memory-only queue, so a launch-time failure degrades the SDK (queued events are
/// lost on process death instead of surviving it) rather than crashing or silently no-oping
/// the entire pipeline. Not public — advanced callers constructing their own `FileDiskQueue`
/// directly already see and can handle its `throws`; this fallback exists only for the one-call
/// composition root, which structurally cannot propagate an error to its caller.
final class EphemeralInMemoryDiskQueue: DiskQueue {
    private var events: [Event] = []
    private let lock = NSLock()

    func enqueue(_ event: Event) throws {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
    }

    func peek(limit: Int) throws -> [Event] {
        lock.lock(); defer { lock.unlock() }
        return Array(events.prefix(limit))
    }

    func remove(eventIds: Set<String>) throws {
        lock.lock(); defer { lock.unlock() }
        events.removeAll { eventIds.contains($0.eventId) }
    }

    func count() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return events.count
    }

    func sizeInBytes() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return (try? JSONEncoder().encode(events))?.count ?? 0
    }
}
