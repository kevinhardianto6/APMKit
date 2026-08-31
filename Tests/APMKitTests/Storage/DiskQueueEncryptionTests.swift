import Testing
import Foundation
import CryptoKit
@testable import APMKit

private final class FakeKeyStore: DiskQueueKeyStore {
    let fixedKey: SymmetricKey
    init(_ key: SymmetricKey = SymmetricKey(size: .bits256)) { self.fixedKey = key }
    func key() -> SymmetricKey { fixedKey }
}

@Suite("AESGCMDiskQueueEncryption — SEC-08 (feat-014)")
struct DiskQueueEncryptionTests {
    @Test("round-trips through encrypt/decrypt")
    func roundTrips() throws {
        let encryption = AESGCMDiskQueueEncryption(keyStore: FakeKeyStore())
        let plaintext = "{\"type\":\"network\",\"attrs\":{}}".data(using: .utf8)!

        let ciphertext = try encryption.encrypt(plaintext)
        let decrypted = try encryption.decrypt(ciphertext)

        #expect(decrypted == plaintext)
    }

    @Test("ciphertext does not contain the plaintext as a readable substring")
    func ciphertextDoesNotContainPlaintext() throws {
        let encryption = AESGCMDiskQueueEncryption(keyStore: FakeKeyStore())
        let plaintext = "phone number 081234567890".data(using: .utf8)!

        let ciphertext = try encryption.encrypt(plaintext)

        #expect(!dataContains(ciphertext, plaintext))
        // Also not readable as any UTF-8 substring containing the raw digits.
        if let asString = String(data: ciphertext, encoding: .utf8) {
            #expect(!asString.contains("081234567890"))
        }
    }

    @Test("decrypting with the wrong key fails")
    func decryptingWithWrongKeyFails() throws {
        let encryption = AESGCMDiskQueueEncryption(keyStore: FakeKeyStore())
        let ciphertext = try encryption.encrypt("secret".data(using: .utf8)!)

        let wrongKeyEncryption = AESGCMDiskQueueEncryption(keyStore: FakeKeyStore())
        #expect(throws: (any Error).self) {
            try wrongKeyEncryption.decrypt(ciphertext)
        }
    }

    @Test("decrypting garbage/corrupted bytes fails rather than crashing")
    func decryptingGarbageFails() {
        let encryption = AESGCMDiskQueueEncryption(keyStore: FakeKeyStore())
        #expect(throws: (any Error).self) {
            try encryption.decrypt(Data("not encrypted at all".utf8))
        }
    }
}
