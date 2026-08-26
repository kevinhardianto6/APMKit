import Testing
import Foundation
@testable import APMKit

@Suite("BreadcrumbRingBuffer — docs/02 §3.4 MOB-13")
struct BreadcrumbRingBufferTests {
    @Test("snapshot returns entries in insertion order")
    func snapshotPreservesOrder() {
        let buffer = BreadcrumbRingBuffer(capacity: 100)
        buffer.add(Breadcrumb(category: .navigation, message: "first"))
        buffer.add(Breadcrumb(category: .userAction, message: "second"))
        buffer.add(Breadcrumb(category: .log, message: "third"))

        #expect(buffer.snapshot().map(\.message) == ["first", "second", "third"])
    }

    @Test("keeps only the last 100, evicting oldest first")
    func keepsLast100() {
        let buffer = BreadcrumbRingBuffer(capacity: 100)
        for i in 0..<105 {
            buffer.add(Breadcrumb(category: .log, message: "crumb-\(i)"))
        }

        let snapshot = buffer.snapshot()
        #expect(snapshot.count == 100)
        #expect(snapshot.first?.message == "crumb-5") // 0..4 evicted
        #expect(snapshot.last?.message == "crumb-104")
    }

    @Test("an empty buffer returns an empty snapshot")
    func emptyBufferReturnsEmptySnapshot() {
        #expect(BreadcrumbRingBuffer(capacity: 100).snapshot().isEmpty)
    }

    @Test("a custom capacity is respected")
    func customCapacityIsRespected() {
        let buffer = BreadcrumbRingBuffer(capacity: 3)
        for i in 0..<5 {
            buffer.add(Breadcrumb(category: .log, message: "crumb-\(i)"))
        }
        #expect(buffer.snapshot().map(\.message) == ["crumb-2", "crumb-3", "crumb-4"])
    }
}
