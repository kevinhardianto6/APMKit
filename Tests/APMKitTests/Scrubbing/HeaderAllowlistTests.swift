import Testing
@testable import APMKit

@Suite("HeaderAllowlist — docs/02 §6.1 SEC-02")
struct HeaderAllowlistTests {
    @Test("keeps only the default-allowed headers")
    func keepsOnlyAllowedHeaders() {
        let headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer secret-token",
            "Cookie": "session=abc123",
            "X-Custom-Header": "whatever",
            "User-Agent": "APMKit/1.0"
        ]
        let filtered = HeaderAllowlist.filter(headers)
        #expect(filtered["Content-Type"] == "application/json")
        #expect(filtered["User-Agent"] == "APMKit/1.0")
        #expect(filtered["Authorization"] == nil)
        #expect(filtered["Cookie"] == nil)
        #expect(filtered["X-Custom-Header"] == nil)
    }

    @Test("matching is case-insensitive on header names")
    func matchingIsCaseInsensitive() {
        let headers = ["content-type": "text/plain", "authorization": "Bearer x"]
        let filtered = HeaderAllowlist.filter(headers)
        #expect(filtered["content-type"] == "text/plain")
        #expect(filtered["authorization"] == nil)
    }

    @Test("an empty header set stays empty")
    func emptyHeadersStayEmpty() {
        #expect(HeaderAllowlist.filter([:]).isEmpty)
    }

    @Test("a custom allowlist can be supplied, overriding the default")
    func customAllowlist() {
        let headers = ["Content-Type": "application/json", "X-App-Version": "3.2.1"]
        let filtered = HeaderAllowlist.filter(headers, allowed: ["X-App-Version"])
        #expect(filtered["X-App-Version"] == "3.2.1")
        #expect(filtered["Content-Type"] == nil)
    }
}
