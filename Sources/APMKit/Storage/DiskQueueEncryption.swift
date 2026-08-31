import Foundation
import CryptoKit

/// SEC-08: AES-GCM encryption for `FileDiskQueue`'s on-disk event files, key from
/// `DiskQueueKeyStore`. Narrow interface so `FileDiskQueue` doesn't need to know CryptoKit
/// exists — same reasoning as every other seam in this SDK (`CrashUserInfoStore`,
/// `HangObserving`, ...).
///
/// **Explicitly does not apply to the crash-report-at-write-time exception (SEC-09).** KSCrash
/// writes its own raw report during the crash itself, outside this SDK's control — this type
/// only encrypts what `FileDiskQueue` itself writes, which *includes* the mapped `crash` event
/// `CrashReportProcessor` produces at next-launch (feat-009) once it reaches the normal
/// pipeline. That's what closes the SEC-09 decision's "dienkripsi saat peluncuran aplikasi
/// berikutnya" assumption — see `archive/features/feat-014.md`.
public protocol DiskQueueEncryption {
    func encrypt(_ data: Data) throws -> Data
    func decrypt(_ data: Data) throws -> Data
}

public struct DiskQueueEncryptionError: Error {}

public final class AESGCMDiskQueueEncryption: DiskQueueEncryption {
    private let keyStore: DiskQueueKeyStore

    public init(keyStore: DiskQueueKeyStore) {
        self.keyStore = keyStore
    }

    public func encrypt(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: keyStore.key())
        guard let combined = sealed.combined else { throw DiskQueueEncryptionError() }
        return combined
    }

    public func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: keyStore.key())
    }
}
