import Testing
@testable import APMKit

@Suite("APMKit package scaffold")
struct APMKitTests {
    @Test("package builds and links")
    func packageLinks() {
        #expect(true)
    }
}
