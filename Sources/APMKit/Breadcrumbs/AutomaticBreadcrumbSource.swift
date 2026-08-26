import Foundation
import Network
#if os(iOS)
import UIKit
#endif

/// Wires MOB-12's automatic breadcrumb sources — app lifecycle and connectivity changes —
/// into a `BreadcrumbRingBuffer`. `start()`/`stop()` mirror `SyncEngine`'s explicit-lifecycle
/// pattern: nothing self-starts silently.
///
/// **Screen transitions are deliberately NOT here.** True automatic screen tracking on iOS
/// needs method swizzling (e.g. `UIViewController.viewDidAppear`), which this SDK avoids by
/// design (`CONSTITUTION.md` rule #1: never crash the host app) — swizzling is invasive,
/// carries real undefined-behavior risk, and can silently conflict with another SDK (Firebase,
/// say) swizzling the same method, with any resulting crash landing on this SDK's reputation
/// regardless of whose swizzle actually broke. See `APM.recordScreen(_:)` and the opt-in
/// `APMTrackedViewController`/`View.apmScreen(_:)` helpers instead — one visible line per
/// screen, zero runtime patching.
public final class AutomaticBreadcrumbSource {
    private let breadcrumbs: BreadcrumbRingBuffer
    private var observerTokens: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "kit.apm.breadcrumbs.connectivity")

    public init(breadcrumbs: BreadcrumbRingBuffer = .shared) {
        self.breadcrumbs = breadcrumbs
    }

    public func start() {
        #if os(iOS)
        startLifecycleObservers()
        #endif
        startConnectivityObserver()
    }

    public func stop() {
        let center = NotificationCenter.default
        observerTokens.forEach { center.removeObserver($0) }
        observerTokens.removeAll()
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    #if os(iOS)
    private static let lifecycleMappings: [(Notification.Name, String)] = [
        (UIApplication.didBecomeActiveNotification, "app_did_become_active"),
        (UIApplication.willResignActiveNotification, "app_will_resign_active"),
        (UIApplication.didEnterBackgroundNotification, "app_did_enter_background"),
        (UIApplication.willEnterForegroundNotification, "app_will_enter_foreground"),
        (UIApplication.willTerminateNotification, "app_will_terminate")
    ]

    private func startLifecycleObservers() {
        let center = NotificationCenter.default
        for (name, message) in Self.lifecycleMappings {
            let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.recordLifecycle(message)
            }
            observerTokens.append(token)
        }
    }
    #endif

    /// `internal`, not `private`: real notification callbacks call this, and tests call it
    /// directly to verify the mapping without needing a real `UIApplication` lifecycle event
    /// (which the host macOS test toolchain can't produce at all — see AGENTS.md's
    /// host-vs-iOS verification note).
    func recordLifecycle(_ message: String) {
        breadcrumbs.add(Breadcrumb(category: .lifecycle, message: message))
    }

    private func startConnectivityObserver() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.recordConnectivity(satisfied: path.status == .satisfied)
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor
    }

    /// `internal`, not `private`: same reasoning as `recordLifecycle` — real
    /// `NWPathMonitor` callbacks call this; tests call it directly rather than trying to
    /// force a real network state change deterministically.
    func recordConnectivity(satisfied: Bool) {
        breadcrumbs.add(Breadcrumb(category: .network, message: satisfied ? "connectivity_restored" : "connectivity_lost"))
    }
}
