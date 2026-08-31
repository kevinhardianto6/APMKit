import Testing
import Foundation
import CryptoKit
@testable import APMKit

@Suite("CertificatePinningConfiguration — SEC-11 backup-pin enforcement")
struct CertificatePinningConfigurationTests {
    @Test("fails to construct with no backup pins at all — backup is mandatory, not optional")
    func failsWithEmptyBackupPins() {
        let primary = Data([0x01, 0x02])
        #expect(CertificatePinningConfiguration(primaryPin: primary, backupPins: []) == nil)
    }

    @Test("fails to construct when every 'backup' is just a duplicate of the primary — that isn't a backup")
    func failsWhenBackupsAreOnlyDuplicatesOfPrimary() {
        let primary = Data([0x01, 0x02])
        #expect(CertificatePinningConfiguration(primaryPin: primary, backupPins: [primary, primary]) == nil)
    }

    @Test("succeeds with at least one backup pin distinct from the primary")
    func succeedsWithADistinctBackupPin() throws {
        let primary = Data([0x01, 0x02])
        let backup = Data([0x03, 0x04])
        let config = try #require(CertificatePinningConfiguration(primaryPin: primary, backupPins: [primary, backup]))
        #expect(config.acceptedPins == Set([primary, backup]))
    }

    @Test("pin(forCertificateDER:) is SHA-256 over the raw DER bytes")
    func pinIsSHA256OfDER() {
        let der = Data("not a real certificate, just bytes for hashing".utf8)
        let expected = Data(SHA256.hash(data: der))
        #expect(CertificatePinningConfiguration.pin(forCertificateDER: der) == expected)
    }
}
