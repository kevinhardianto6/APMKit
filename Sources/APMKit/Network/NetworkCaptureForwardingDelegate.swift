import Foundation

/// Implemented by the host app to handle server-trust challenges (e.g. certificate pinning)
/// on an `APM.instrumentedSession()`. `NetworkCaptureDelegate` forwards only
/// `NSURLAuthenticationMethodServerTrust` challenges here — everything else is handled with
/// `.performDefaultHandling` before it ever reaches this delegate — and observes the
/// disposition the host chooses so a resulting `NSURLErrorCancelled` on task completion can
/// be correctly mapped to `ssl_pinning_rejected` instead of a plain `cancelled`
/// (docs/01 §5 implementation note).
public protocol NetworkCaptureForwardingDelegate: AnyObject {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    )
}
