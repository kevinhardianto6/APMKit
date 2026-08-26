import Testing
import Foundation
@testable import APMKit

@Suite("FailureCategoryMapper — docs/01 §5")
struct FailureCategoryMapperTests {
    private func nsError(_ code: Int, domain: String = NSURLErrorDomain) -> NSError {
        NSError(domain: domain, code: code, userInfo: nil)
    }

    @Test("a pinning rejection always maps to ssl_pinning_rejected, regardless of error code")
    func pinningRejectionWins() {
        let error = nsError(NSURLErrorCancelled)
        #expect(FailureCategoryMapper.map(error: error, pinningRejected: true) == .sslPinningRejected)
    }

    @Test("a normal cancel (no pinning rejection observed) maps to cancelled, not ssl_pinning_rejected")
    func normalCancelIsNotPinningRejection() {
        let error = nsError(NSURLErrorCancelled)
        #expect(FailureCategoryMapper.map(error: error, pinningRejected: false) == .cancelled)
    }

    @Test("timeout maps to timeout")
    func timeout() {
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorTimedOut), pinningRejected: false) == .timeout)
    }

    @Test("DNS failures map to dns")
    func dnsFailures() {
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorCannotFindHost), pinningRejected: false) == .dns)
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorDNSLookupFailed), pinningRejected: false) == .dns)
    }

    @Test("connectivity-loss errors map to connectivity")
    func connectivity() {
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorNotConnectedToInternet), pinningRejected: false) == .connectivity)
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorNetworkConnectionLost), pinningRejected: false) == .connectivity)
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorCannotConnectToHost), pinningRejected: false) == .connectivity)
    }

    @Test("certificate errors map to ssl_certificate")
    func sslCertificate() {
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorServerCertificateUntrusted), pinningRejected: false) == .sslCertificate)
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorServerCertificateHasBadDate), pinningRejected: false) == .sslCertificate)
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorClientCertificateRejected), pinningRejected: false) == .sslCertificate)
    }

    @Test("secure connection failure maps to tls_handshake")
    func tlsHandshake() {
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorSecureConnectionFailed), pinningRejected: false) == .tlsHandshake)
    }

    @Test("unmapped NSURLError codes fall back to unknown")
    func unmappedCodeFallsBackToUnknown() {
        #expect(FailureCategoryMapper.map(error: nsError(NSURLErrorBadURL), pinningRejected: false) == .unknown)
    }

    @Test("a non-NSURLErrorDomain error falls back to unknown")
    func nonURLErrorDomainFallsBackToUnknown() {
        #expect(FailureCategoryMapper.map(error: nsError(1, domain: "SomeOtherDomain"), pinningRejected: false) == .unknown)
    }

    @Test("tlsPhaseReached: no dates reached means none")
    func tlsPhaseNone() {
        #expect(FailureCategoryMapper.tlsPhaseReached(secureConnectionStart: nil, secureConnectionEnd: nil) == .none)
    }

    @Test("tlsPhaseReached: start without end means started")
    func tlsPhaseStarted() {
        #expect(FailureCategoryMapper.tlsPhaseReached(secureConnectionStart: Date(), secureConnectionEnd: nil) == .started)
    }

    @Test("tlsPhaseReached: start and end means completed")
    func tlsPhaseCompleted() {
        let now = Date()
        #expect(FailureCategoryMapper.tlsPhaseReached(secureConnectionStart: now, secureConnectionEnd: now.addingTimeInterval(0.01)) == .completed)
    }
}
