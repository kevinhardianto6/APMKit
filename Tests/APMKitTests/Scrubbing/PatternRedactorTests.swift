import Testing
@testable import APMKit

@Suite("PatternRedactor — docs/02 §6.1 SEC-05")
struct PatternRedactorTests {
    @Test("redacts an Indonesian mobile number starting with 08")
    func redactsLocalFormatPhone() {
        let input = "Gagal mengirim OTP ke 081234567890"
        #expect(PatternRedactor.redact(input) == "Gagal mengirim OTP ke [redacted]")
    }

    @Test("redacts an Indonesian mobile number in +62 format")
    func redactsInternationalFormatPhone() {
        let input = "contact +6281234567890 please"
        #expect(PatternRedactor.redact(input) == "contact [redacted] please")
    }

    @Test("redacts an email address")
    func redactsEmail() {
        let input = "user email: someone@example.com"
        #expect(PatternRedactor.redact(input) == "user email: [redacted]")
    }

    @Test("redacts a JWT-like token as a single unit")
    func redactsJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dQw4w9WgXcQ_abcdefg"
        let input = "Authorization: Bearer \(jwt)"
        #expect(PatternRedactor.redact(input) == "Authorization: Bearer [redacted]")
    }

    @Test("redacts a bare run of 10+ digits not matching phone or JWT")
    func redactsLongDigitRun() {
        let input = "account 9988776655443322 flagged"
        #expect(PatternRedactor.redact(input) == "account [redacted] flagged")
    }

    @Test("does not touch a string with no matching pattern")
    func leavesCleanStringUntouched() {
        let input = "user tapped checkout button"
        #expect(PatternRedactor.redact(input) == input)
    }

    @Test("does not redact short digit runs (below the 10-digit floor)")
    func leavesShortDigitsUntouched() {
        let input = "retry count 42, page 7"
        #expect(PatternRedactor.redact(input) == input)
    }

    @Test("redacts multiple distinct matches in the same string")
    func redactsMultipleMatchesInOneString() {
        let input = "call 081234567890 or email someone@example.com"
        #expect(PatternRedactor.redact(input) == "call [redacted] or email [redacted]")
    }
}
