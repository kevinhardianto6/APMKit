import Foundation
import CryptoKit
import Security

/// Persists the disk queue's at-rest encryption key (SEC-08) across launches. Narrow
/// interface, same reasoning as `CrashUserInfoStore`/`HangObserving` (feat-009/010): the real
/// Keychain-backed implementation is one line to swap for a fake in tests, without needing a
/// real Keychain (or a real device/Simulator) for the parts of `FileDiskQueue` that don't care
/// where the key came from.
public protocol DiskQueueKeyStore {
    /// Returns the persistent key, generating and storing one on first access. Must never
    /// throw or crash (`CONSTITUTION.md` rule #1) — a Keychain failure is handled by falling
    /// back to a process-lifetime-only key (see `KeychainDiskQueueKeyStore`), not by
    /// propagating an error into the disk-queue write path.
    func key() -> SymmetricKey
}

/// Real Keychain-backed key store. `kSecAttrAccessibleAfterFirstUnlock` (not
/// `...WhenUnlocked`) so the SDK can still write to the encrypted queue from the background —
/// same reasoning SEC-07 already applies to `FileProtectionType.completeUntilFirstUserAuthentication`
/// (`FileDiskQueue.applyDataProtection`): available as soon as the device has been unlocked
/// once since boot, not only while actively unlocked right now.
public final class KeychainDiskQueueKeyStore: DiskQueueKeyStore {
    private let service: String
    private let account: String
    private let lock = NSLock()
    /// Falls back to here if Keychain reads AND writes both fail — keeps this launch's queue
    /// usable (encrypted with *some* key) rather than either crashing or writing unencrypted.
    /// A previous run's queued files become unreadable in that case (a new random key can't
    /// decrypt them) — an acceptable trade-off for "never throw/crash" over "never lose data
    /// to a Keychain outage," matching how disk-write failures elsewhere in this SDK are
    /// already counted as dropped (MOB-27) rather than escalated.
    private var inMemoryFallback: SymmetricKey?

    public init(service: String = "kit.apm.diskqueue", account: String = "encryption-key") {
        self.service = service
        self.account = account
    }

    public func key() -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        if let existing = readKey() { return existing }
        if let fallback = inMemoryFallback { return fallback }

        let generated = SymmetricKey(size: .bits256)
        if storeKey(generated) {
            return generated
        }
        inMemoryFallback = generated
        return generated
    }

    private func readKey() -> SymmetricKey? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    @discardableResult
    private func storeKey(_ key: SymmetricKey) -> Bool {
        let keyData = key.withUnsafeBytes { Data($0) }
        SecItemDelete(baseQuery() as CFDictionary) // clear any partial/stale item first

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = keyData
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
