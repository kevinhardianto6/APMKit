import Testing
import Foundation
@testable import APMKit

@Suite("UserIdentity — docs/01 §2.1, MOB-28, SEC-06")
struct UserIdentityTests {
    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "UserIdentityTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @Test("setUser stores the raw string exactly — no hashing, no transformation")
    func setUserStoresRawValueExactly() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let raw = "081234567890" // phone-number-shaped, deliberately — must NOT be hashed
        UserIdentity.setUser(id: raw, userDefaults: defaults)

        #expect(UserIdentity.currentUserId(userDefaults: defaults) == raw)
    }

    @Test("accepts any free-form string without validation (email, arbitrary text, ...)")
    func acceptsAnyFreeFormString() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        for raw in ["someone@example.com", "internal-user-42", "not an email or phone at all!! 🎉"] {
            UserIdentity.setUser(id: raw, userDefaults: defaults)
            #expect(UserIdentity.currentUserId(userDefaults: defaults) == raw)
        }
    }

    @Test("without setUser, falls back to a stable random id persisted per install")
    func fallsBackToStableRandomId() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = UserIdentity.currentUserId(userDefaults: defaults)
        let second = UserIdentity.currentUserId(userDefaults: defaults)

        #expect(first == second)
        #expect(UUID(uuidString: first) != nil)
    }

    @Test("different UserDefaults stores (simulating different installs) get different fallback ids")
    func differentStoresGetDifferentFallbackIds() throws {
        let (defaultsA, suiteA) = try isolatedDefaults()
        let (defaultsB, suiteB) = try isolatedDefaults()
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }

        #expect(UserIdentity.currentUserId(userDefaults: defaultsA) != UserIdentity.currentUserId(userDefaults: defaultsB))
    }

    @Test("an explicitly-set id takes precedence over the fallback and persists across calls")
    func explicitIdTakesPrecedenceAndPersists() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Establish a fallback first, as if the app ran before setUser was ever called.
        let fallback = UserIdentity.currentUserId(userDefaults: defaults)

        UserIdentity.setUser(id: "explicit-user-id", userDefaults: defaults)
        #expect(UserIdentity.currentUserId(userDefaults: defaults) == "explicit-user-id")
        #expect(UserIdentity.currentUserId(userDefaults: defaults) != fallback)

        // Still there on a "later" call, unchanged.
        #expect(UserIdentity.currentUserId(userDefaults: defaults) == "explicit-user-id")
    }

    @Test("install_id and user_id fallback are independent — setting one doesn't affect the other")
    func installIdAndUserIdFallbackAreIndependent() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let installId = InstallIdentity.current(userDefaults: defaults)
        let userIdFallback = UserIdentity.currentUserId(userDefaults: defaults)

        #expect(installId != userIdFallback)
    }

    // MARK: - user_id_source (docs/01 §2.2, MOB-28 extended)

    @Test("without setUser, currentUserIdentity reports source .generated alongside the fallback id")
    func currentUserIdentityReportsGeneratedWhenNoSetUser() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let (id, source) = UserIdentity.currentUserIdentity(userDefaults: defaults)
        #expect(source == .generated)
        #expect(UUID(uuidString: id) != nil)
    }

    @Test("after setUser, currentUserIdentity reports source .host alongside the exact explicit value")
    func currentUserIdentityReportsHostAfterSetUser() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        UserIdentity.setUser(id: "explicit-user-id", userDefaults: defaults)
        let (id, source) = UserIdentity.currentUserIdentity(userDefaults: defaults)

        #expect(id == "explicit-user-id")
        #expect(source == .host)
    }

    @Test("currentUserId and currentUserIdentity never disagree — same id whether read alone or paired with its source")
    func currentUserIdAndCurrentUserIdentityAgree() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(UserIdentity.currentUserId(userDefaults: defaults) == UserIdentity.currentUserIdentity(userDefaults: defaults).id)

        UserIdentity.setUser(id: "explicit-user-id", userDefaults: defaults)
        #expect(UserIdentity.currentUserId(userDefaults: defaults) == UserIdentity.currentUserIdentity(userDefaults: defaults).id)
    }
}
