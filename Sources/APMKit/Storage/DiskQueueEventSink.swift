import Foundation

/// Thin `EventSink` adapter placing a `DiskQueue` at the end of the pipeline. Keeps
/// `DiskQueue` (feat-002) free of any dependency on the capture/scrub layer's vocabulary —
/// it only knows about `Event`, not `EventSink`.
///
/// Failures are swallowed rather than thrown (`CONSTITUTION.md` rule #1: SDK must never
/// throw into the host app) — proper failure counting (events written vs dropped) is
/// feat-010's self-health counters (MOB-27); until then, a disk write failure here is
/// silent by design rather than a partial/incorrect implementation of that requirement.
public final class DiskQueueEventSink: EventSink {
    private let diskQueue: DiskQueue

    public init(diskQueue: DiskQueue) {
        self.diskQueue = diskQueue
    }

    public func receive(_ event: Event) {
        try? diskQueue.enqueue(event)
    }
}
