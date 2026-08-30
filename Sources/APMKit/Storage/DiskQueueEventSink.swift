import Foundation

/// Thin `EventSink` adapter placing a `DiskQueue` at the end of the pipeline. Keeps
/// `DiskQueue` (feat-002) free of any dependency on the capture/scrub layer's vocabulary —
/// it only knows about `Event`, not `EventSink`.
///
/// Failures are swallowed rather than thrown (`CONSTITUTION.md` rule #1: SDK must never
/// throw into the host app) — but counted, not silently vanished (MOB-27, feat-010).
public final class DiskQueueEventSink: EventSink {
    private let diskQueue: DiskQueue
    private let selfHealth: SelfHealthCounters

    public init(diskQueue: DiskQueue, selfHealth: SelfHealthCounters = .shared) {
        self.diskQueue = diskQueue
        self.selfHealth = selfHealth
    }

    public func receive(_ event: Event) {
        do {
            try diskQueue.enqueue(event)
            selfHealth.recordWritten()
        } catch {
            selfHealth.recordDropped()
        }
    }
}
