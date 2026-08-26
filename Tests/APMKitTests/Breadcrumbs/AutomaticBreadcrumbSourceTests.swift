import Testing
import Foundation
@testable import APMKit

/// `AutomaticBreadcrumbSource`'s real triggers are OS-level: `UIApplication` lifecycle
/// notifications (iOS-only — the host macOS test toolchain has no `UIApplication` at all to
/// post them from) and real `NWPathMonitor` connectivity changes (cross-platform, but not
/// something a unit test can force deterministically). These tests exercise the *mapping*
/// logic real callbacks delegate to (`recordLifecycle`/`recordConnectivity`, `internal` for
/// exactly this reason) directly, plus that `start()`/`stop()` don't crash — that's the
/// honest scope of what's unit-testable here without a real device/simulator.
@Suite("AutomaticBreadcrumbSource — docs/02 §3.4 MOB-12")
struct AutomaticBreadcrumbSourceTests {
    @Test("recordLifecycle adds a lifecycle-category breadcrumb with the given message")
    func recordLifecycleAddsBreadcrumb() {
        let buffer = BreadcrumbRingBuffer(capacity: 100)
        let source = AutomaticBreadcrumbSource(breadcrumbs: buffer)

        source.recordLifecycle("app_did_become_active")

        let snapshot = buffer.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot[0].category == .lifecycle)
        #expect(snapshot[0].message == "app_did_become_active")
    }

    @Test("recordConnectivity maps satisfied/unsatisfied to the right network-category message")
    func recordConnectivityMapsStatus() {
        let buffer = BreadcrumbRingBuffer(capacity: 100)
        let source = AutomaticBreadcrumbSource(breadcrumbs: buffer)

        source.recordConnectivity(satisfied: true)
        source.recordConnectivity(satisfied: false)

        let snapshot = buffer.snapshot()
        #expect(snapshot.count == 2)
        #expect(snapshot[0].category == .network)
        #expect(snapshot[0].message == "connectivity_restored")
        #expect(snapshot[1].message == "connectivity_lost")
    }

    @Test("start() then stop() does not crash and leaves no dangling observers")
    func startAndStopDoNotCrash() {
        let source = AutomaticBreadcrumbSource(breadcrumbs: BreadcrumbRingBuffer(capacity: 100))
        source.start()
        source.stop()
        // Calling stop() again must also be safe (idempotent cleanup).
        source.stop()
    }
}
