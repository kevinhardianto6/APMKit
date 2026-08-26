import Foundation

/// Ring buffer of the last 100 breadcrumbs (MOB-13). Deliberately **not** an `EventSink` and
/// never writes to disk on its own — breadcrumbs are only useful as context *around* an
/// error/crash, so they're attached as a snapshot at the moment `ManualReporter.logError`
/// (or, later, feat-009's crash handler) actually builds one, rather than each being queued
/// as its own disk event. This also means: a screen the app never crashes near never costs a
/// disk write, however many breadcrumbs accumulate and roll off.
///
/// `.shared` is this SDK's one piece of ambient/global state (unlike `sink`/`sessionManager`
/// elsewhere, which are always explicitly injected) — a lock-protected in-memory FIFO is safe
/// to be a singleton in a way a disk queue or network session is not. `APM.breadcrumb(_:
/// category:)` writes here; tests should construct their own isolated instance rather than
/// touching `.shared`, to avoid cross-test pollution.
public final class BreadcrumbRingBuffer {
    public static let shared = BreadcrumbRingBuffer()

    private let capacity: Int
    private var storage: [Breadcrumb] = []
    private let lock = NSLock()

    public init(capacity: Int = 100) {
        self.capacity = capacity
    }

    public func add(_ breadcrumb: Breadcrumb) {
        lock.lock()
        storage.append(breadcrumb)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
        lock.unlock()
    }

    /// Oldest-first snapshot of everything currently retained.
    public func snapshot() -> [Breadcrumb] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
