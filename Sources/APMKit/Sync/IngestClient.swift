import Foundation

/// Real `POST /v1/ingest` implementation (docs/01 §7). Uses a plain `URLSession` passed in
/// by the caller — **must never** be `APM.instrumentedSession()` (MOB-09 anti-loop: uploading
/// on an instrumented session would generate a `network` event for every upload, which would
/// itself need uploading). The default `init` constructs a bare session with no custom
/// delegate at all, so there is structurally no path back into `NetworkCaptureDelegate`.
///
/// **SEC-10:** the default session's configuration (`SDKOwnedSessionConfiguration`) floors
/// TLS at 1.2, independent of the host app's own ATS settings. **SEC-12:** there is no code
/// path anywhere in this type, `outcome(response:error:)`, or `SyncEngine`'s handling of its
/// result that retries a failed request over a weaker connection — every failure keeps the
/// batch on disk and retries the identical request against the identical session/URL.
///
/// **SEC-11 (feat-015):** `pinning`, when supplied, attaches a `PinningSessionDelegate` to
/// this client's own session. Left `nil` (the default), the session is built exactly as
/// feat-011 left it — no delegate at all, preserving the `session.delegate == nil` assertion
/// MOB-09's anti-loop test already makes.
public final class IngestClient: IngestUploading {
    private let endpoint: IngestEndpoint
    /// Internal, not private: `MOB-09`'s anti-loop guarantee ("uploader MUST use a separate,
    /// non-instrumented URLSession") is a real invariant, not an implementation detail — it's
    /// asserted directly in tests (`session.delegate == nil`) via `@testable import`.
    let session: URLSession
    private let encoder = JSONEncoder()

    /// `pinning` is ignored when `session` is passed explicitly (tests that supply their own
    /// session already control its delegate). Otherwise: no `pinning` → the plain feat-011
    /// session, exactly as before this feature — no delegate, no pinning code path active.
    /// `pinning` supplied → a session built with `PinningSessionDelegate`. `CertificatePinning`
    /// bundles the pin material with the `RemoteConfigStore` that carries its kill switch, so
    /// there is no way to pass one without the other (SEC-11).
    public init(
        endpoint: IngestEndpoint,
        pinning: CertificatePinning? = nil,
        session: URLSession? = nil
    ) {
        self.endpoint = endpoint
        if let session {
            self.session = session
        } else if let pinning {
            let delegate = PinningSessionDelegate(pinning: pinning)
            self.session = URLSession(configuration: SDKOwnedSessionConfiguration.make(), delegate: delegate, delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: SDKOwnedSessionConfiguration.make())
        }
    }

    public func upload(envelope: Envelope, completion: @escaping (UploadOutcome) -> Void) {
        do {
            let json = try encoder.encode(envelope)
            let gzipped = try GzipEncoder.gzip(json)

            var request = URLRequest(url: endpoint.url)
            request.httpMethod = "POST"
            request.setValue(endpoint.appKey, forHTTPHeaderField: "X-APM-Key")
            request.setValue("\(SDKInfo.current.name)/\(SDKInfo.current.version)", forHTTPHeaderField: "X-APM-Sdk")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
            request.httpBody = gzipped

            session.dataTask(with: request) { _, response, error in
                completion(Self.outcome(response: response, error: error))
            }.resume()
        } catch {
            // Encoding/compression failure never throws into the caller (CONSTITUTION.md
            // rule #1) — treated as a transport failure so the batch stays on disk and is
            // retried like any other transient failure, rather than being silently dropped.
            completion(.transportFailure)
        }
    }

    private static func outcome(response: URLResponse?, error: Error?) -> UploadOutcome {
        guard error == nil, let http = response as? HTTPURLResponse else {
            return .transportFailure
        }
        switch http.statusCode {
        case 202:
            return .accepted
        case 400:
            return .rejected
        case 401, 403:
            return .unauthorized
        case 413:
            return .payloadTooLarge
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            return .rateLimited(retryAfterSeconds: retryAfter)
        case 500...599:
            return .serverError
        default:
            // Not in the §7 table — the conservative default is "keep data, back off",
            // never "drop the batch", since an unrecognized code might just mean the server
            // added a new status we haven't been told about yet.
            return .serverError
        }
    }
}
