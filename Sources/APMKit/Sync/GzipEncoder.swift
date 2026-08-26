import Foundation
import Compression

/// Produces true RFC 1952 gzip framing, needed because `POST /v1/ingest` requires
/// `Content-Encoding: gzip` (docs/01 §7). Apple's `Compression` framework has no direct gzip
/// algorithm constant — `compression_encode_buffer` with `COMPRESSION_ZLIB` produces a *raw*
/// DEFLATE stream (no zlib header/trailer, despite the name), so gzip framing is assembled
/// by hand: a 10-byte header, the raw deflate payload, then a CRC-32 + uncompressed-size
/// trailer. This is the standard workaround used by every gzip-in-Swift implementation that
/// avoids depending on a third-party library — stays within the "Foundation + Compression"
/// dependency budget (`CONSTITUTION.md`).
enum GzipEncoder {
    enum GzipError: Error { case compressionFailed }

    static func gzip(_ data: Data) throws -> Data {
        let deflated = try rawDeflate(data)

        var output = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff])
        output.append(deflated)

        var crc = CRC32.checksum(data).littleEndian
        withUnsafeBytes(of: &crc) { output.append(contentsOf: $0) }

        var isize = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &isize) { output.append(contentsOf: $0) }

        return output
    }

    private static func rawDeflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        // Deflate never expands data by more than a small, bounded overhead; this capacity
        // is a generous upper bound so `compression_encode_buffer` never needs to be retried.
        let dstCapacity = data.count + (data.count / 2) + 256
        var dst = [UInt8](repeating: 0, count: dstCapacity)
        let srcBytes = [UInt8](data)

        let compressedSize = dst.withUnsafeMutableBufferPointer { dstPtr -> Int in
            srcBytes.withUnsafeBufferPointer { srcPtr -> Int in
                compression_encode_buffer(
                    dstPtr.baseAddress!, dstCapacity,
                    srcPtr.baseAddress!, srcBytes.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard compressedSize > 0 else { throw GzipError.compressionFailed }
        return Data(dst.prefix(compressedSize))
    }
}
