import Foundation

/// Receives a freshly captured event. Capture → **Scrub** → Disk → Sync
/// (`CONSTITUTION.md`) — Network Capture never touches the disk queue directly; it hands
/// events to whatever the pipeline's next stage is. Scrubbing (feat-004) is what actually
/// implements this protocol in front of the disk queue (feat-002).
public protocol EventSink: AnyObject {
    func receive(_ event: Event)
}
