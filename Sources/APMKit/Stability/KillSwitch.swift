import Foundation

/// MOB-21: "Mematuhi kill switch" — `enabled: false` in the remote config disables the SDK
/// app-wide, without a new release. This is the capture-side half of that guarantee: an
/// `EventSink` that drops everything instead of forwarding it, the moment `enabled` is false.
///
/// Sits as the **outermost** stage of the pipeline (`CONSTITUTION.md`: Capture → Scrub → Disk
/// → Sync) — wraps `Scrubber`, not the other way around, so a disabled SDK does zero work
/// beyond the `Bool` check: no scrubbing, no disk write. The other half of "disables the SDK"
/// is `SyncEngine`'s own `isEnabled` closure (feat-010), which stops uploads independently —
/// together they cover both directions data could still move while "disabled."
///
/// Events dropped here are intentional suppression, not a failure — they are **not** counted
/// via `SelfHealthCounters.recordDropped` (MOB-27 tracks internal failures; an operator
/// deliberately turning the SDK off is not one).
public final class KillSwitch: EventSink {
    private let downstream: EventSink
    private let store: RemoteConfigStore

    public init(downstream: EventSink, store: RemoteConfigStore) {
        self.downstream = downstream
        self.store = store
    }

    public func receive(_ event: Event) {
        guard store.current.enabled else { return }
        downstream.receive(event)
    }
}
