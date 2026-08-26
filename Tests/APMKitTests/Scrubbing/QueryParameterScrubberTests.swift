import Testing
@testable import APMKit

@Suite("QueryParameterScrubber — docs/02 §6.1 SEC-03")
struct QueryParameterScrubberTests {
    @Test("redacts all parameter values by default, keeping only names")
    func redactsAllValuesByDefault() {
        let result = QueryParameterScrubber.scrub(queryString: "msisdn=0812xxxx&otp=123456")
        #expect(result == "msisdn=[redacted]&otp=[redacted]")
    }

    @Test("an allowlisted parameter name keeps its real value")
    func allowlistedParameterKeepsValue() {
        let result = QueryParameterScrubber.scrub(queryString: "page=2&token=secret", valueAllowlist: ["page"])
        #expect(result == "page=2&token=[redacted]")
    }

    @Test("an empty query string stays empty")
    func emptyQueryStringStaysEmpty() {
        #expect(QueryParameterScrubber.scrub(queryString: "") == "")
    }

    @Test("a single parameter is handled without a trailing separator artifact")
    func singleParameter() {
        #expect(QueryParameterScrubber.scrub(queryString: "q=search+term") == "q=[redacted]")
    }
}
