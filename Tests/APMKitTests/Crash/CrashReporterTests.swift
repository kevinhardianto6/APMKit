import Testing
import Foundation
@testable import APMKit

private final class FakeCrashUserInfoStore: CrashUserInfoStore {
    private(set) var values: [String: String?] = [:]

    func setUserInfo(_ value: String?, forKey key: String) {
        values[key] = value
    }
}

/// Only `startBreadcrumbMirroring()` is exercised here — `install()` touches real KSCrash
/// signal/mach handlers and must never run inside `swift test` (it would install into the
/// test process itself). Real crash capture is verified on-device (see `FEATURES.md`
/// feat-009 evidence / manual-verification list).
@Suite("CrashReporter breadcrumb mirroring — SEC-09, MOB-13")
struct CrashReporterTests {
    @Test("adding a breadcrumb mirrors a scrubbed snapshot into the user-info store")
    func addingBreadcrumbMirrorsSnapshot() throws {
        let buffer = BreadcrumbRingBuffer(capacity: 100)
        let userInfoStore = FakeCrashUserInfoStore()
        let reporter = CrashReporter(breadcrumbs: buffer, userInfoStore: userInfoStore)
        reporter.startBreadcrumbMirroring()

        buffer.add(Breadcrumb(category: .navigation, message: "OrderScreen"))

        let json = try #require(userInfoStore.values["breadcrumbs"] ?? nil)
        let decoded = try JSONDecoder().decode([Breadcrumb].self, from: Data(json.utf8))
        #expect(decoded.map(\.message) == ["OrderScreen"])
    }

    @Test("PII in a breadcrumb message is redacted before it reaches the user-info store")
    func breadcrumbPIIIsRedactedBeforeMirroring() throws {
        let buffer = BreadcrumbRingBuffer(capacity: 100)
        let userInfoStore = FakeCrashUserInfoStore()
        let reporter = CrashReporter(breadcrumbs: buffer, userInfoStore: userInfoStore)
        reporter.startBreadcrumbMirroring()

        buffer.add(Breadcrumb(category: .log, message: "failed to reach user 081234567890"))

        let json = try #require(userInfoStore.values["breadcrumbs"] ?? nil)
        #expect(!json.contains("081234567890"))
        #expect(json.contains("[redacted]"))
    }

    @Test("starting mirroring immediately syncs whatever was already in the buffer")
    func startingMirroringSyncsExistingBreadcrumbs() throws {
        let buffer = BreadcrumbRingBuffer(capacity: 100)
        buffer.add(Breadcrumb(category: .navigation, message: "already here"))
        let userInfoStore = FakeCrashUserInfoStore()
        let reporter = CrashReporter(breadcrumbs: buffer, userInfoStore: userInfoStore)

        reporter.startBreadcrumbMirroring()

        let json = try #require(userInfoStore.values["breadcrumbs"] ?? nil)
        #expect(json.contains("already here"))
    }
}
