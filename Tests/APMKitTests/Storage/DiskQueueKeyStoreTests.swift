import Testing
import Foundation
import Security
@testable import APMKit

/// Real Keychain, not a fake — confirmed empirically before writing this suite that
/// `SecItemAdd`/`SecItemCopyMatching` work from a plain `swift test` process on macOS with no
/// special entitlements. Each test uses a unique service/account (a UUID suffix) and cleans up
/// after itself, so repeated runs don't accumulate stale items in the developer's real login
/// keychain.
///
/// **feat-015 note:** every `store.key()` call and manual `SecItemDelete` below goes through
/// `KeychainTestLock` — added after feat-015's `TLSMockServer` test infra (also real-Keychain
/// backed) started intermittently causing `KeychainDiskQueueKeyStore.storeKey`'s `SecItemAdd`
/// to lose a race under Swift Testing's parallel execution, silently returning a key that never
/// actually got persisted. See `KeychainTestLock`'s doc comment for the full story.
@Suite("KeychainDiskQueueKeyStore — SEC-08 key persistence (feat-014)")
struct DiskQueueKeyStoreTests {
    private func makeStore() -> (store: KeychainDiskQueueKeyStore, cleanup: () -> Void) {
        let service = "kit.apm.diskqueue-test-\(UUID().uuidString)"
        let account = "encryption-key"
        let store = KeychainDiskQueueKeyStore(service: service, account: account)
        let cleanup = {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            KeychainTestLock.sync { SecItemDelete(query as CFDictionary) }
        }
        return (store, cleanup)
    }

    @Test("a fresh service/account generates a key on first access")
    func generatesKeyOnFirstAccess() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let key = KeychainTestLock.sync { store.key() }
        #expect(key.bitCount == 256)
    }

    @Test("the same store instance returns the same key across calls")
    func sameInstanceReturnsSameKey() {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        #expect(KeychainTestLock.sync { store.key() } == KeychainTestLock.sync { store.key() })
    }

    @Test("a NEW store instance, same service/account, reads back the SAME persisted key — real Keychain round-trip, not in-memory only")
    func newInstanceSameServiceReadsBackSameKey() {
        let service = "kit.apm.diskqueue-test-\(UUID().uuidString)"
        let account = "encryption-key"
        let first = KeychainDiskQueueKeyStore(service: service, account: account)
        let firstKey = KeychainTestLock.sync { first.key() }

        let second = KeychainDiskQueueKeyStore(service: service, account: account)
        let secondKey = KeychainTestLock.sync { second.key() }

        #expect(firstKey == secondKey)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        KeychainTestLock.sync { SecItemDelete(query as CFDictionary) }
    }

    @Test("different service/account pairs get independent keys")
    func differentServiceAccountGetsIndependentKey() {
        let (storeA, cleanupA) = makeStore()
        let (storeB, cleanupB) = makeStore()
        defer { cleanupA(); cleanupB() }

        #expect(KeychainTestLock.sync { storeA.key() } != KeychainTestLock.sync { storeB.key() })
    }
}
