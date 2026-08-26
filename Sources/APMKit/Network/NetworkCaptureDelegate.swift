import Foundation
import Network

/// `URLSessionTaskDelegate` that captures every request on an instrumented session as a
/// `network` or `network_failure` event (docs/01 §4.1/§4.2, docs/02 §3.1 MOB-01/02/03/10).
///
/// All internal state access is defensive per `CONSTITUTION.md` rule #1 (SDK must never
/// crash or throw into the host app) — a malformed task/response never propagates, it's
/// simply not captured.
public final class NetworkCaptureDelegate: NSObject, URLSessionTaskDelegate {
    /// Optional: host app's certificate-pinning (or other trust-evaluation) logic.
    public weak var forwardingDelegate: NetworkCaptureForwardingDelegate?

    private let sink: EventSink
    private let sessionManager: SessionManager
    /// Hosts never captured, even on an instrumented session — MOB-10 anti-loop: the SDK's
    /// own ingest host (wired in by feat-005) must never be instrumented, or every upload
    /// would generate an event that needs uploading.
    private let excludedHosts: Set<String>

    private let stateQueue = DispatchQueue(label: "kit.apm.networkcapture.state")
    private var pendingMetrics: [Int: URLSessionTaskMetrics] = [:]
    private var pinningRejectedTaskIdentifiers: Set<Int> = []

    public init(
        sink: EventSink,
        sessionManager: SessionManager,
        excludedHosts: Set<String> = []
    ) {
        self.sink = sink
        self.sessionManager = sessionManager
        self.excludedHosts = excludedHosts
    }

    // MARK: - URLSessionTaskDelegate

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let forwardingDelegate else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        forwardingDelegate.urlSession(session, task: task, didReceive: challenge) { [weak self] disposition, credential in
            if disposition == .cancelAuthenticationChallenge || disposition == .rejectProtectionSpace {
                self?.markPinningRejected(taskIdentifier: task.taskIdentifier)
            }
            completionHandler(disposition, credential)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        stateQueue.sync { pendingMetrics[task.taskIdentifier] = metrics }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let metrics = stateQueue.sync { pendingMetrics.removeValue(forKey: task.taskIdentifier) }
        let pinningRejected = stateQueue.sync { pinningRejectedTaskIdentifiers.remove(task.taskIdentifier) != nil }

        guard let request = task.originalRequest, let url = request.url, let host = url.host else { return }
        guard !excludedHosts.contains(host) else { return }

        let method = request.httpMethod ?? "GET"
        let path = url.path.isEmpty ? "/" : url.path
        let transaction = metrics?.transactionMetrics.last
        let durationMs = metrics.map { Int($0.taskInterval.duration * 1000) } ?? 0

        if let nsError = error as NSError? {
            emitFailureEvent(
                host: host, path: path, method: method,
                error: nsError, pinningRejected: pinningRejected,
                transaction: transaction, durationMs: durationMs
            )
            return
        }

        guard let httpResponse = task.response as? HTTPURLResponse else { return }
        emitSuccessEvent(host: host, path: path, method: method, response: httpResponse, transaction: transaction, durationMs: durationMs)

        if httpResponse.statusCode >= 400 {
            emitHTTPErrorEvent(host: host, path: path, method: method, statusCode: httpResponse.statusCode, durationMs: durationMs)
        }
    }

    // MARK: - Event construction

    private func emitSuccessEvent(
        host: String, path: String, method: String,
        response: HTTPURLResponse, transaction: URLSessionTaskTransactionMetrics?, durationMs: Int
    ) {
        var attrs: [String: AttributeValue] = [
            "host": .string(host),
            "path": .string(path),
            "method": .string(method),
            "status_code": .int(response.statusCode),
            "duration_ms": .int(durationMs)
        ]

        if let transaction {
            if let dns = msBetween(transaction.domainLookupStartDate, transaction.domainLookupEndDate) {
                attrs["dns_ms"] = .int(dns)
            }
            if let tcp = msBetween(transaction.connectStartDate, transaction.connectEndDate) {
                attrs["tcp_ms"] = .int(tcp)
            }
            if let tls = msBetween(transaction.secureConnectionStartDate, transaction.secureConnectionEndDate) {
                attrs["tls_ms"] = .int(tls)
            }
            if let ttfb = msBetween(transaction.requestStartDate, transaction.responseStartDate) {
                attrs["ttfb_ms"] = .int(ttfb)
            }
            attrs["req_bytes"] = .int(Int(transaction.countOfRequestBodyBytesSent))
            attrs["res_bytes"] = .int(Int(transaction.countOfResponseBodyBytesReceived))
            if let proto = transaction.networkProtocolName {
                attrs["protocol"] = .string(proto)
            }
            if let version = transaction.negotiatedTLSProtocolVersion {
                attrs["tls_version"] = .string(tlsVersionString(version))
            }
            attrs["reused_connection"] = .bool(transaction.isReusedConnection)
        }

        sink.receive(Event(type: "network", seq: sessionManager.nextSequenceNumber(), attrs: attrs))
    }

    private func emitFailureEvent(
        host: String, path: String, method: String,
        error: NSError, pinningRejected: Bool,
        transaction: URLSessionTaskTransactionMetrics?, durationMs: Int
    ) {
        let category = FailureCategoryMapper.map(error: error, pinningRejected: pinningRejected)
        let phase = FailureCategoryMapper.tlsPhaseReached(
            secureConnectionStart: transaction?.secureConnectionStartDate,
            secureConnectionEnd: transaction?.secureConnectionEndDate
        )

        var attrs: [String: AttributeValue] = [
            "host": .string(host),
            "path": .string(path),
            "method": .string(method),
            "failure_category": .string(category.rawValue),
            "error_domain": .string(error.domain),
            "error_code": .int(error.code),
            "duration_ms": .int(durationMs),
            "tls_phase_reached": .string(phase.rawValue)
        ]
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            attrs["underlying_domain"] = .string(underlying.domain)
            attrs["underlying_code"] = .int(underlying.code)
        }

        sink.receive(Event(type: "network_failure", seq: sessionManager.nextSequenceNumber(), attrs: attrs))
    }

    /// docs/01 §4.2/§5 `http_error` (MOB-02b) — a *received* 4xx/5xx response, not a
    /// transport-level `NSURLError`. Per the now-official §4.2 table, `status_code` is
    /// required here and `error_domain`/`error_code` are NOT — those are required only for
    /// real transport failures (`emitFailureEvent`), which is why this event omits them
    /// rather than synthesizing placeholder values.
    private func emitHTTPErrorEvent(host: String, path: String, method: String, statusCode: Int, durationMs: Int) {
        let attrs: [String: AttributeValue] = [
            "host": .string(host),
            "path": .string(path),
            "method": .string(method),
            "failure_category": .string(FailureCategory.httpError.rawValue),
            "status_code": .int(statusCode),
            "duration_ms": .int(durationMs)
        ]
        sink.receive(Event(type: "network_failure", seq: sessionManager.nextSequenceNumber(), attrs: attrs))
    }

    // MARK: - Helpers

    private func markPinningRejected(taskIdentifier: Int) {
        stateQueue.sync { _ = pinningRejectedTaskIdentifiers.insert(taskIdentifier) }
    }

    private func msBetween(_ start: Date?, _ end: Date?) -> Int? {
        guard let start, let end else { return nil }
        return Int(end.timeIntervalSince(start) * 1000)
    }

    private func tlsVersionString(_ version: tls_protocol_version_t) -> String {
        switch version {
        case .TLSv10: return "TLSv1.0"
        case .TLSv11: return "TLSv1.1"
        case .TLSv12: return "TLSv1.2"
        case .TLSv13: return "TLSv1.3"
        case .DTLSv10: return "DTLSv1.0"
        case .DTLSv12: return "DTLSv1.2"
        @unknown default: return "unknown"
        }
    }
}
