import Testing
import Foundation
@testable import APMKit

private final class AcceptingForwardingDelegate: NetworkCaptureForwardingDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }
}

private final class RejectingForwardingDelegate: NetworkCaptureForwardingDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

private final class DummyChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

@Suite("NetworkCaptureDelegate — docs/02 §3.1, MOB-01/02/03/10")
struct NetworkCaptureDelegateTests {
    private func attr(_ event: Event, _ key: String) -> AttributeValue? { event.attrs[key] }

    private func string(_ event: Event, _ key: String) -> String? {
        if case .string(let value)? = attr(event, key) { return value }
        return nil
    }

    private func int(_ event: Event, _ key: String) -> Int? {
        if case .int(let value)? = attr(event, key) { return value }
        return nil
    }

    // MARK: - Real requests (docs/02 §3.1 "menangkap metrik seluruh HTTP request")

    @Test("a successful real request produces a network event with the exact §4.1 fields")
    func successfulRequestProducesNetworkEvent() async throws {
        let server = MockHTTPServer { _, _ in .respond(status: 200, body: Data("ok".utf8)) }
        try server.start()
        defer { server.stop() }

        let sink = CollectingEventSink()
        let (session, _) = APM.instrumentedSession(sink: sink, sessionManager: SessionManager())

        let url = URL(string: "http://127.0.0.1:\(server.port)/hello")!
        session.dataTask(with: url).resume()

        let events = await waitForEvents(sink, count: 1)
        #expect(events.count == 1)
        guard let event = events.first else { return }
        #expect(event.type == "network")
        #expect(string(event, "host") == "127.0.0.1")
        #expect(string(event, "path") == "/hello")
        #expect(string(event, "method") == "GET")
        #expect(int(event, "status_code") == 200)
        #expect(int(event, "duration_ms") != nil)
    }

    @Test("a 4xx/5xx response produces both a network event and a network_failure(http_error) event")
    func httpErrorResponseProducesBothEvents() async throws {
        let server = MockHTTPServer { _, _ in .respond(status: 500) }
        try server.start()
        defer { server.stop() }

        let sink = CollectingEventSink()
        let (session, _) = APM.instrumentedSession(sink: sink, sessionManager: SessionManager())

        let url = URL(string: "http://127.0.0.1:\(server.port)/broken")!
        session.dataTask(with: url).resume()

        let events = await waitForEvents(sink, count: 2)
        #expect(events.count == 2)

        let networkEvent = events.first { $0.type == "network" }
        let failureEvent = events.first { $0.type == "network_failure" }
        #expect(networkEvent != nil)
        #expect(int(networkEvent!, "status_code") == 500)

        #expect(failureEvent != nil)
        #expect(string(failureEvent!, "failure_category") == "http_error")
        #expect(int(failureEvent!, "status_code") == 500)
    }

    @Test("a real timeout produces a network_failure event with failure_category timeout")
    func realTimeoutProducesTimeoutFailure() async throws {
        let server = MockHTTPServer { _, _ in .hang }
        try server.start()
        defer { server.stop() }

        let sink = CollectingEventSink()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 0.3
        let (session, _) = APM.instrumentedSession(configuration: configuration, sink: sink, sessionManager: SessionManager())

        let url = URL(string: "http://127.0.0.1:\(server.port)/slow")!
        session.dataTask(with: url).resume()

        let events = await waitForEvents(sink, count: 1)
        #expect(events.count == 1)
        guard let event = events.first else { return }
        #expect(event.type == "network_failure")
        #expect(string(event, "failure_category") == "timeout")
        #expect(string(event, "error_domain") == NSURLErrorDomain)
    }

    @Test("a real app-initiated cancel (no pinning involved) maps to cancelled")
    func realCancelMapsToCancelled() async throws {
        let server = MockHTTPServer { _, _ in .hang }
        try server.start()
        defer { server.stop() }

        let sink = CollectingEventSink()
        let (session, _) = APM.instrumentedSession(sink: sink, sessionManager: SessionManager())

        let url = URL(string: "http://127.0.0.1:\(server.port)/slow")!
        let task = session.dataTask(with: url)
        task.resume()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let events = await waitForEvents(sink, count: 1)
        #expect(events.count == 1)
        #expect(string(events.first!, "failure_category") == "cancelled")
    }

    @Test("hosts in excludedHosts are never captured (MOB-10 anti-loop)")
    func excludedHostsAreNotCaptured() async throws {
        let server = MockHTTPServer { _, _ in .respond(status: 200) }
        try server.start()
        defer { server.stop() }

        let sink = CollectingEventSink()
        let (session, _) = APM.instrumentedSession(
            sink: sink, sessionManager: SessionManager(), excludedHosts: ["127.0.0.1"]
        )

        let url = URL(string: "http://127.0.0.1:\(server.port)/hello")!
        session.dataTask(with: url).resume()

        // Give the delegate callback a moment to (not) fire, then assert nothing arrived.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(sink.events.isEmpty)
    }

    // MARK: - Pinning rejection vs. normal cancel (docs/01 §5 implementation note)

    @Test("a server-trust challenge rejected via the forwarding delegate maps a later NSURLErrorCancelled to ssl_pinning_rejected")
    func pinningRejectionObservedThroughForwardingDelegate() async throws {
        let sink = CollectingEventSink()
        let sessionManager = SessionManager()
        let delegate = NetworkCaptureDelegate(sink: sink, sessionManager: sessionManager)
        // forwardingDelegate is `weak` (matches the real APM.instrumentedSession() usage,
        // where the host app owns its pinning delegate) — the test must keep its own
        // strong reference, or it's deallocated before the challenge fires.
        let forwarder = RejectingForwardingDelegate()
        delegate.forwardingDelegate = forwarder

        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://example.invalid/secure")!)
        let challenge = makeServerTrustChallenge(host: "example.invalid")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            delegate.urlSession(session, task: task, didReceive: challenge) { _, _ in
                continuation.resume()
            }
        }

        // Per docs/01 §5: a rejected pinning challenge surfaces as a plain NSURLErrorCancelled
        // on task completion — this is exactly the ambiguous signal the delegate must resolve
        // using the challenge outcome it already observed above.
        delegate.urlSession(session, task: task, didCompleteWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))

        #expect(sink.events.count == 1)
        #expect(string(sink.events.first!, "failure_category") == "ssl_pinning_rejected")
    }

    @Test("a server-trust challenge the forwarding delegate accepts does NOT mark a later cancel as pinning-rejected")
    func acceptedChallengeDoesNotMarkPinningRejection() async throws {
        let sink = CollectingEventSink()
        let sessionManager = SessionManager()
        let delegate = NetworkCaptureDelegate(sink: sink, sessionManager: sessionManager)
        let forwarder = AcceptingForwardingDelegate()
        delegate.forwardingDelegate = forwarder

        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://example.invalid/secure")!)
        let challenge = makeServerTrustChallenge(host: "example.invalid")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            delegate.urlSession(session, task: task, didReceive: challenge) { _, _ in
                continuation.resume()
            }
        }

        // An unrelated, later app-initiated cancel on the same task — must NOT be
        // misattributed to pinning just because a trust challenge occurred earlier.
        delegate.urlSession(session, task: task, didCompleteWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))

        #expect(sink.events.count == 1)
        #expect(string(sink.events.first!, "failure_category") == "cancelled")
    }

    private func makeServerTrustChallenge(host: String) -> URLAuthenticationChallenge {
        let protectionSpace = URLProtectionSpace(
            host: host, port: 443, protocol: "https", realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        return URLAuthenticationChallenge(
            protectionSpace: protectionSpace, proposedCredential: nil,
            previousFailureCount: 0, failureResponse: nil, error: nil,
            sender: DummyChallengeSender()
        )
    }
}
