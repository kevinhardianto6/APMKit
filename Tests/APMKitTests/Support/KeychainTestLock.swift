import Foundation

/// Every test in this target that touches real Keychain Services (`SecItemAdd`,
/// `SecItemCopyMatching`, `SecKeyCreateRandomKey`, ...) must serialize through this lock.
///
/// Confirmed empirically (feat-015's `TLSMockServer.swift`, which generates real EC identities
/// via the default keychain for TLS pinning tests): Swift Testing's parallel test execution
/// drives concurrent Keychain access hard enough to trigger legacy-keychain-backend races —
/// intermittent `SecItemAdd` failures under load — even though every caller uses independent,
/// uniquely-tagged items with no application-level shared state. Adding `TLSMockServer`'s tests
/// measurably raised `DiskQueueKeyStoreTests`' (feat-014, SEC-08) pre-existing keychain
/// round-trip test from never-flaking to intermittently reading back a *different* key than was
/// stored — the actual production code (`KeychainDiskQueueKeyStore.storeKey`) was silently
/// losing the race on `SecItemAdd`, not a bug in either test. One shared lock across every
/// keychain-touching test file in this target is the fix, not scoped to a single suite.
enum KeychainTestLock {
    private static let queue = DispatchQueue(label: "apmkit-tests.keychain-serial")

    static func sync<T>(_ body: () throws -> T) rethrows -> T {
        try queue.sync(execute: body)
    }
}
