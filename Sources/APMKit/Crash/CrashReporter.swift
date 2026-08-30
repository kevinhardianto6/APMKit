import Foundation
import KSCrashRecording

/// Installs and configures KSCrash (docs/02 §3.5, MOB-15/16/17) — wraps a mature crash
/// library rather than hand-rolling signal/mach handlers (`CONSTITUTION.md` platform
/// invariants, docs/00 §11 decision 4). This is the one component intentionally running while
/// the app is dying; everything it does at crash time is KSCrash's own async-signal-safe
/// internals, not ours — our job is limited to configuration and, afterward, reading what it
/// wrote (`CrashReportProcessor`).
public final class CrashReporter {
    public static let shared = CrashReporter()

    private let breadcrumbs: BreadcrumbRingBuffer
    private let userInfoStore: CrashUserInfoStore

    public init(breadcrumbs: BreadcrumbRingBuffer = .shared, userInfoStore: CrashUserInfoStore = KSCrash.shared) {
        self.breadcrumbs = breadcrumbs
        self.userInfoStore = userInfoStore
    }

    /// Wires the ring buffer so every breadcrumb addition mirrors a scrubbed snapshot into
    /// KSCrash's per-key user info — an mmap'd sidecar KSCrash can fold into a report with no
    /// crash-time allocation (MOB-13: breadcrumbs attached to every crash). Safe to call
    /// standalone in tests; unlike `install()`, it touches no real signal/mach handlers.
    public func startBreadcrumbMirroring() {
        breadcrumbs.onAdd = { [weak self] _ in self?.syncBreadcrumbs() }
        syncBreadcrumbs()
    }

    private func syncBreadcrumbs() {
        userInfoStore.setUserInfo(CrashBreadcrumbEncoder.scrubbedJSON(breadcrumbs.snapshot()), forKey: "breadcrumbs")
    }

    /// Installs KSCrash's signal/mach-exception/NSException/C++-exception/termination
    /// monitors. Hang detection (`KSCrashMonitorTypeWatchdog`, MOB-18) is feat-010's scope —
    /// deliberately not enabled here (`CONSTITUTION.md`: one feature active at a time, build
    /// order is mandatory). Call once, as early as possible during app launch, before
    /// `APM.processPendingCrashReports`.
    ///
    /// - Parameter installPath: overrides KSCrash's default install directory (normally
    ///   derived from the app's own Caches directory). Production callers should never pass
    ///   this — it exists so `IOSCrashHarnessTests` can point two *separate* process launches
    ///   (two `xcodebuild test -only-testing:` invocations, each a fresh app container on the
    ///   Simulator) at the same fixed on-disk location, which is what makes "crash in process
    ///   A, read back in process B" reproducible there.
    @discardableResult
    public func install(installPath: String? = nil) -> Bool {
        let configuration = KSCrashConfiguration()
        // .watchdog added in feat-010 (MOB-18) — deliberately excluded in feat-009 (see the
        // dated CONSTITUTION.md decision) until hang detection was actually in scope. Powers
        // both `HangDetector`'s live observation and, for genuinely fatal watchdog
        // terminations (0x8badf00d), the existing next-launch pipeline via `CrashReportMapper`.
        configuration.monitors = [.machException, .signal, .cppException, .nsException, .userReported, .termination, .watchdog]
        // SEC-09: memory introspection can pull arbitrary object/string contents near the
        // stack pointer or CPU registers into the raw report — a PII risk this SDK doesn't
        // take. This is already the framework default; set explicitly so the choice reads as
        // deliberate rather than an accident of upstream defaults.
        configuration.enableMemoryIntrospection = false
        configuration.addConsoleLogToReport = false
        if let installPath {
            configuration.installPath = installPath
        }

        startBreadcrumbMirroring()

        do {
            try KSCrash.shared.install(with: configuration)
            return true
        } catch {
            return false
        }
    }
}
