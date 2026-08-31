import Testing
import Foundation
import Security
@testable import APMKit

/// Sanity tests for the `TLSMockServer` test-infrastructure (feat-015 cert-pinning support).
/// These aren't testing SDK behavior — they're proving the fixture itself does a *real* TLS
/// handshake and produces a certificate that round-trips through Security.framework, so
/// feat-015's actual pinning tests can build on top of it with confidence.
struct TLSMockServerTests {

    /// A trust-everything `URLSessionDelegate` — the point is only to prove the TLS handshake
    /// itself completes for real (not `-1200`/`NSURLErrorSecureConnectionFailed`), not to
    /// exercise any pin-checking logic (that's feat-015's job, against this fixture).
    final class AcceptAllDelegate: NSObject, URLSessionDelegate {
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        }
    }

    @Test
    func performsRealTLSHandshakeAndReturnsCannedResponse() async throws {
        let generated = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "localhost")
        defer { generated.cleanup() }

        let server = TLSMockServer(identity: generated.identity)
        let port = try server.start()
        defer { server.stop() }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config, delegate: AcceptAllDelegate(), delegateQueue: nil)

        let url = URL(string: "https://127.0.0.1:\(port)/")!
        let (data, response) = try await session.data(from: url)

        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 202)
        #expect(data.isEmpty)
    }

    @Test
    func certificateDERRoundTripsThroughSecCertificate() throws {
        let generated = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "roundtrip.example")
        defer { generated.cleanup() }

        let rebuilt = try #require(SecCertificateCreateWithData(nil, generated.certificateDER as CFData))
        let rebuiltData = SecCertificateCopyData(rebuilt) as Data

        #expect(rebuiltData == generated.certificateDER)
    }

    @Test
    func canGenerateTwoDistinctIdentitiesInOneRun() throws {
        let identityA = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "server-a.example")
        defer { identityA.cleanup() }
        let identityB = try TLSTestIdentityFactory.makeSelfSignedIdentity(commonName: "server-b.example")
        defer { identityB.cleanup() }

        #expect(identityA.certificateDER != identityB.certificateDER)
    }
}
