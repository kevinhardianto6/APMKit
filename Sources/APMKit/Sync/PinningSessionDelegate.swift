import Foundation

/// SEC-11: `URLSessionDelegate` attached to an `IngestClient`/`RemoteConfigFetcher` session
/// **only when the host app has explicitly opted into pinning** — never constructed, and
/// never assigned as a session's delegate, when pinning is off (the default). That is what
/// makes "OFF behaves identically to feat-011, zero pinning code path active" true by
/// construction rather than by a runtime flag this type would otherwise need to check.
///
/// Reads `remoteConfigStore.current.disabledFeatures` on every challenge, not once at init —
/// SEC-11's kill switch (`RemoteConfig.disabledFeatures == ["cert_pinning"]`) must take effect
/// on the next connection attempt without an app restart, the same way feat-010's master
/// `enabled` switch already does for `KillSwitch`.
///
/// **"Stop pinning" never means "stop verifying" (SEC-12).** When the kill switch is on, this
/// delegate calls `performDefaultHandling` — the connection falls back to feat-011's plain TLS
/// floor (`SDKOwnedSessionConfiguration`'s TLS 1.2 minimum, full system CA validation), not to
/// an unverified connection. When pinning is active and the presented chain doesn't match a
/// configured pin, this delegate cancels the challenge — fail closed, the request never
/// completes, the batch stays on disk exactly like every other `IngestClient` failure mode
/// (feat-011's confirmed guarantee: no path anywhere retries over a weaker connection).
final class PinningSessionDelegate: NSObject, URLSessionDelegate {
    private let pinning: CertificatePinning

    /// The `disabledFeatures` entry that kills pinning specifically, without touching
    /// feat-010's master `enabled` switch or any other feature.
    static let killSwitchFeatureName = "cert_pinning"

    init(pinning: CertificatePinning) {
        self.pinning = pinning
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard !pinning.remoteConfigStore.current.disabledFeatures.contains(Self.killSwitchFeatureName) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if CertificatePinningValidator.matches(trust: trust, pins: pinning.configuration.acceptedPins) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
