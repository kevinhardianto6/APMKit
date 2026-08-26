import Testing
import Foundation
@testable import APMKit

@Suite("GzipEncoder — docs/01 §7 Content-Encoding: gzip")
struct GzipEncoderTests {
    @Test("output starts with the gzip magic bytes")
    func hasGzipMagicBytes() throws {
        let compressed = try GzipEncoder.gzip(Data("hello world".utf8))
        #expect(compressed[compressed.startIndex] == 0x1f)
        #expect(compressed[compressed.startIndex + 1] == 0x8b)
    }

    @Test("round-trips arbitrary text through gunzip unchanged")
    func roundTripsText() throws {
        let original = Data(String(repeating: "the quick brown fox jumps over the lazy dog. ", count: 50).utf8)
        let compressed = try GzipEncoder.gzip(original)
        let decompressed = try GunzipHelper.gunzip(compressed)
        #expect(decompressed == original)
    }

    @Test("round-trips real envelope JSON unchanged")
    func roundTripsEnvelopeJSON() throws {
        let envelope = Envelope(
            app: AppInfo(id: "com.example.app", version: "1.0", build: "1"),
            device: DeviceInfo(os: "iOS", osVersion: "17.4", model: "iPhone14,2", locale: "id_ID", timezone: "Asia/Jakarta"),
            installId: UUID().uuidString,
            sessionId: UUID().uuidString,
            userId: nil,
            events: [Event(type: "network", seq: 1, attrs: ["host": .string("api.example.com")])]
        )
        let json = try JSONEncoder().encode(envelope)
        let compressed = try GzipEncoder.gzip(json)
        let decompressed = try GunzipHelper.gunzip(compressed)
        let decoded = try JSONDecoder().decode(Envelope.self, from: decompressed)
        #expect(decoded == envelope)
    }

    @Test("compresses meaningfully smaller than the original for repetitive data")
    func compressesSmaller() throws {
        let original = Data(String(repeating: "a", count: 10_000).utf8)
        let compressed = try GzipEncoder.gzip(original)
        #expect(compressed.count < original.count / 10)
    }

    @Test("handles empty input")
    func handlesEmptyInput() throws {
        let compressed = try GzipEncoder.gzip(Data())
        let decompressed = try GunzipHelper.gunzip(compressed)
        #expect(decompressed.isEmpty)
    }
}
