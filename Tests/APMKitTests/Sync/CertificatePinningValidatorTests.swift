import Testing
import Foundation
import Security
@testable import APMKit

/// Pin-matching logic against a real `SecTrust` built from real, `TLSTestIdentityFactory`
/// -generated certificates — no live socket needed for this part, since `SecTrust` can be
/// constructed directly from certificate data (`SecTrustCreateWithCertificates`). The live-
/// handshake path (real accept/reject over a real TLS connection) is covered separately in
/// `CertificatePinningTests.swift`, which drives this same validator through
/// `PinningSessionDelegate`/`IngestClient`.
@Suite("CertificatePinningValidator — real certificates, no live handshake")
struct CertificatePinningValidatorTests {
    private func trust(for certificate: SecCertificate) throws -> SecTrust {
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }

    @Test("matches when the leaf certificate's hash is in the pin set")
    func matchesLeafPin() throws {
        let identity = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "pin-match.example")
        defer { identity.cleanup() }

        let trust = try trust(for: identity.certificate)
        let pin = CertificatePinningConfiguration.pin(forCertificateDER: identity.certificateDER)

        #expect(CertificatePinningValidator.matches(trust: trust, pins: [pin]))
    }

    @Test("does not match a certificate whose hash isn't in the pin set — fails closed")
    func rejectsUnrelatedCertificate() throws {
        let presented = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "presented.example")
        defer { presented.cleanup() }
        let unrelated = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "unrelated.example")
        defer { unrelated.cleanup() }

        let trust = try trust(for: presented.certificate)
        let unrelatedPin = CertificatePinningConfiguration.pin(forCertificateDER: unrelated.certificateDER)

        #expect(!CertificatePinningValidator.matches(trust: trust, pins: [unrelatedPin]))
    }

    @Test("an empty pin set never matches, regardless of the certificate")
    func emptyPinSetNeverMatches() throws {
        let identity = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "no-pins.example")
        defer { identity.cleanup() }

        let trust = try trust(for: identity.certificate)
        #expect(!CertificatePinningValidator.matches(trust: trust, pins: []))
    }
}
