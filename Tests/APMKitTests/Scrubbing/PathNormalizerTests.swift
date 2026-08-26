import Testing
@testable import APMKit

@Suite("PathNormalizer — docs/02 §6.1 SEC-03b")
struct PathNormalizerTests {
    @Test("replaces a long-digit-run segment (phone-number-shaped) with {id}")
    func replacesLongDigitSegment() {
        #expect(PathNormalizer.normalize("/user/628123456789/profile") == "/user/{id}/profile")
    }

    @Test("replaces a UUID segment with {id}")
    func replacesUUIDSegment() {
        #expect(PathNormalizer.normalize("/orders/3f2b1c8a-5e6f-4a7b-8c9d-0e1f2a3b4c5d/items") == "/orders/{id}/items")
    }

    @Test("leaves short, word-like segments untouched")
    func leavesWordSegmentsUntouched() {
        #expect(PathNormalizer.normalize("/api/v2/user/profile") == "/api/v2/user/profile")
    }

    @Test("leaves a short digit segment (below the 5-digit floor) untouched")
    func leavesShortDigitSegmentUntouched() {
        #expect(PathNormalizer.normalize("/api/v2/items") == "/api/v2/items")
    }

    @Test("normalizes multiple id-like segments in the same path")
    func normalizesMultipleSegments() {
        #expect(PathNormalizer.normalize("/user/628123456789/order/998877665544") == "/user/{id}/order/{id}")
    }

    @Test("root path is unaffected")
    func rootPathUnaffected() {
        #expect(PathNormalizer.normalize("/") == "/")
    }
}
