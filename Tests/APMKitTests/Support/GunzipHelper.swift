import Foundation
import Compression
@testable import APMKit

/// Test-only inverse of `GzipEncoder`, used to prove gzip round-trips correctly without
/// depending on any external tool. Strips the 10-byte gzip header and 8-byte trailer,
/// inflates the raw deflate payload via the same `Compression` framework, and verifies the
/// trailer's CRC-32 + size against the result.
enum GunzipHelper {
    enum GunzipError: Error { case malformedGzip, decompressionFailed, checksumMismatch }

    static func gunzip(_ data: Data) throws -> Data {
        guard data.count >= 18, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else {
            throw GunzipError.malformedGzip
        }
        let payload = data.dropFirst(10).dropLast(8)
        let trailer = data.suffix(8)

        // `Data` subsequences aren't guaranteed 4-byte aligned, so `.load(as: UInt32.self)`
        // can crash with "misaligned raw pointer" — assemble the little-endian value by hand
        // instead of taking that risk.
        let expectedCRC = readUInt32LE(trailer.prefix(4))
        let expectedSize = Int(readUInt32LE(trailer.suffix(4)))

        let inflated = try rawInflate(Data(payload), expectedSize: expectedSize)
        guard CRC32.checksum(inflated) == expectedCRC else { throw GunzipError.checksumMismatch }
        return inflated
    }

    private static func readUInt32LE(_ bytes: Data.SubSequence) -> UInt32 {
        var value: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt32(byte) << (8 * index)
        }
        return value
    }

    private static func rawInflate(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var dst = [UInt8](repeating: 0, count: expectedSize)
        let srcBytes = [UInt8](data)

        let decodedSize = dst.withUnsafeMutableBufferPointer { dstPtr -> Int in
            srcBytes.withUnsafeBufferPointer { srcPtr -> Int in
                compression_decode_buffer(
                    dstPtr.baseAddress!, expectedSize,
                    srcPtr.baseAddress!, srcBytes.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard decodedSize == expectedSize else { throw GunzipError.decompressionFailed }
        return Data(dst)
    }
}
