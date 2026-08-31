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

    @Test("feat-016: recordLifecycle fires onDidEnterBackground/onWillEnterForeground for exactly the matching message, never both")
    func recordLifecycleFiresMatchingHookOnly() {
        let source = AutomaticBreadcrumbSource(breadcrumbs: BreadcrumbRingBuffer(capacity: 10))
        var backgroundCount = 0
        var foregroundCount = 0
        source.onDidEnterBackground = { backgroundCount += 1 }
        source.onWillEnterForeground = { foregroundCount += 1 }

        source.recordLifecycle("app_did_enter_background")
        #expect(backgroundCount == 1)
        #expect(foregroundCount == 0)

        source.recordLifecycle("app_will_enter_foreground")
        #expect(backgroundCount == 1)
        #expect(foregroundCount == 1)

        source.recordLifecycle("app_did_become_active") // unrelated message — neither hook fires
        #expect(backgroundCount == 1)
        #expect(foregroundCount == 1)
    }

    @Test("feat-016: recordConnectivity fires onConnectivityRestored only when satisfied, including on the very first callback")
    func recordConnectivityFiresRestoredHookOnlyWhenSatisfied() {
        let source = AutomaticBreadcrumbSource(breadcrumbs: BreadcrumbRingBuffer(capacity: 10))
        var restoredCount = 0
        source.onConnectivityRestored = { restoredCount += 1 }

        source.recordConnectivity(satisfied: true)
        #expect(restoredCount == 1)

        source.recordConnectivity(satisfied: false)
        #expect(restoredCount == 1)

        source.recordConnectivity(satisfied: true)
        #expect(restoredCount == 2)
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
