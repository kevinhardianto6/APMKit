#if os(iOS)
import Testing
import Foundation
@testable import APMKit

/// Real-device/Simulator crash verification (feat-009's actual "Done when" criterion) —
/// deliberately **not** part of the default `swift test` / `./verify.sh test` run. Forcing a
/// real crash and reading it back needs two *separate* process launches, which one XCTest/
/// Swift Testing invocation can't do — the process that crashes doesn't come back to run a
/// second test. So this suite is split into two phases, each run as its own `xcodebuild test`
/// invocation naming exactly one test via `-only-testing:`, against a booted iOS Simulator.
/// Verified working end-to-end on Xcode 26.4 / iOS 18.0 Simulator, 2026-08-28:
///
/// ```
/// xcrun simctl list devices booted             # confirm a device is booted; note its UDID
/// # -destination 'platform=iOS Simulator,name=...' can be ambiguous across arch variants —
/// # id= is what actually resolved reliably.
/// rm -rf /tmp/apmkit-ios-crash-harness         # start clean
///
/// # Phase 1 — forces a real NSException crash. `xcodebuild test` reports this invocation as
/// # crashing (exit 134 inside the run) — that is the point, not a bug. The trailing "()" on
/// # the test name is required for leaf-level -only-testing selection; omitting it, or
/// # omitting the leaf entirely, selects zero or (worse) both tests — Swift Testing runs
/// # tests within a suite in parallel by default, which would run phase 2 concurrently with
/// # phase 1 rather than after it. (`@Suite(.serialized)` below is a second line of defense
/// # against that, but always pass the specific leaf test — don't rely on it alone.)
/// xcodebuild test \
///   -scheme APMKit \
///   -destination 'platform=iOS Simulator,id=<UDID>' \
///   "-only-testing:APMKitTests/IOSCrashHarnessTests/phase1_forceCrash()"
///
/// # Phase 2 — fresh process launch, reads the crash back through the real pipeline.
/// # This invocation should report success.
/// xcodebuild test \
///   -scheme APMKit \
///   -destination 'platform=iOS Simulator,id=<UDID>' \
///   "-only-testing:APMKitTests/IOSCrashHarnessTests/phase2_readBackAfterRelaunch()"
/// ```
///
/// Uses fixed, non-default paths (`installPath` override, `FileDiskQueue` directory) under
/// `/tmp` rather than the app's own container directories — the Simulator reinstalls the test
/// runner into a fresh container UUID on every `xcodebuild test` invocation, so anything under
/// `NSHomeDirectory()`/`NSTemporaryDirectory()` would not actually persist between phase 1 and
/// phase 2 the way it needs to for this to work. Writing to a literal, hardcoded `/tmp` path
/// like this works because Simulator processes aren't kernel-sandboxed the way a real device
/// enforces — confirmed empirically, not just assumed. This is a Simulator-only technique,
/// consistent with this being a manual/Simulator-only verification tool, not something that
/// runs in CI or on a real device.
///
/// See `FEATURES.md` → "Manual verification checklist (pilot)" for when this was last run.
@Suite(
    "IOSCrashHarnessTests — manual, iOS Simulator only, not part of the default test run",
    .serialized
)
struct IOSCrashHarnessTests {
    private static let installPath = "/tmp/apmkit-ios-crash-harness/kscrash"
    private static let queueDirectory = URL(fileURLWithPath: "/tmp/apmkit-ios-crash-harness/queue")

    private static func makeSink() -> (sink: EventSink, sessionManager: SessionManager) {
        let queue = try! FileDiskQueue(directoryURL: queueDirectory)
        let sink = Scrubber(downstream: DiskQueueEventSink(diskQueue: queue))
        return (sink, SessionManager())
    }

    @Test("phase 1: install crash reporting, record a breadcrumb with fake PII, force a real crash")
    func phase1_forceCrash() {
        let (sink, sessionManager) = Self.makeSink()
        let installed = APM.installCrashReporting(sink: sink, sessionManager: sessionManager, installPath: Self.installPath)
        #expect(installed)

        APM.breadcrumb("navigated to OrderScreen", category: .navigation)
        APM.breadcrumb("forced crash for user 081234567890", category: .log)

        NSException(
            name: NSExceptionName("IOSCrashHarnessTestCrash"),
            reason: "forced crash for user 081234567890 during checkout",
            userInfo: nil
        ).raise()

        Issue.record("unreachable — the NSException above should have terminated the process")
    }

    @Test("phase 2: a fresh launch drains the crash from phase 1 through the real pipeline")
    func phase2_readBackAfterRelaunch() async throws {
        let (sink, sessionManager) = Self.makeSink()
        let installed = APM.installCrashReporting(sink: sink, sessionManager: sessionManager, installPath: Self.installPath)
        #expect(installed)

        // Draining happens on a background queue (APMKit.swift) — poll briefly for it to land.
        let queue = try FileDiskQueue(directoryURL: Self.queueDirectory)
        var events: [Event] = []
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            events = try queue.peek(limit: 50)
            if !events.isEmpty { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        let event = try #require(events.first { $0.type == "crash" })

        func string(_ key: String) -> String? {
            if case .string(let value)? = event.attrs[key] { return value }
            return nil
        }

        #expect(string("crash_type") == "exception")
        #expect(string("name") == "IOSCrashHarnessTestCrash")
        #expect(string("reason")?.contains("[redacted]") == true)
        #expect(string("reason")?.contains("081234567890") == false)
        #expect(string("binary_images")?.isEmpty == false)
        let breadcrumbsJSON = try #require(string("breadcrumbs"))
        #expect(breadcrumbsJSON.contains("OrderScreen"))
        #expect(breadcrumbsJSON.contains("[redacted]"))
        #expect(breadcrumbsJSON.contains("081234567890") == false)
    }
}
#endif
