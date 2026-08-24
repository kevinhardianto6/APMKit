import Testing
import Foundation
@testable import APMKit

@Suite("Install identity — docs/01 §2, install_id persists per install")
struct InstallIdentityTests {
    @Test("generates a stable id that persists across calls (simulating relaunch)")
    func persistsAcrossCalls() throws {
        let suiteName = "InstallIdentityTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = InstallIdentity.current(userDefaults: defaults)
        let second = InstallIdentity.current(userDefaults: defaults)

        #expect(first == second)
        #expect(UUID(uuidString: first) != nil)
    }

    @Test("different UserDefaults stores (simulating different installs) get different ids")
    func differentStoresGetDifferentIds() throws {
        let defaultsA = try #require(UserDefaults(suiteName: "InstallIdentityTests.A.\(UUID())"))
        let defaultsB = try #require(UserDefaults(suiteName: "InstallIdentityTests.B.\(UUID())"))

        let idA = InstallIdentity.current(userDefaults: defaultsA)
        let idB = InstallIdentity.current(userDefaults: defaultsB)

        #expect(idA != idB)
    }
}
