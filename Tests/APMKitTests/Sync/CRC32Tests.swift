import Testing
import Foundation
@testable import APMKit

@Suite("CRC32")
struct CRC32Tests {
    @Test("checksum of empty data is 0")
    func emptyDataChecksumIsZero() {
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test("matches the well-known ASCII '123456789' test vector (0xCBF43926)")
    func matchesStandardTestVector() {
        let data = Data("123456789".utf8)
        #expect(CRC32.checksum(data) == 0xCBF43926)
    }

    @Test("different inputs produce different checksums")
    func differentInputsDifferentChecksums() {
        #expect(CRC32.checksum(Data("hello".utf8)) != CRC32.checksum(Data("world".utf8)))
    }
}
