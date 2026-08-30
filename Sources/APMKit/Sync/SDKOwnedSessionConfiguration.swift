import Foundation
import Network

/// The `URLSessionConfiguration` for every connection the SDK originates itself — `IngestClient`
/// (`POST /v1/ingest`) and `RemoteConfigFetcher` (`GET /v1/config`). Not for
/// `APM.instrumentedSession()`, which is the *host app's* traffic and none of this SDK's
/// business to hardcode a TLS floor onto.
///
/// **SEC-10:** explicitly floors TLS at 1.2, rather than resting on whatever the host app's
/// own ATS configuration happens to allow. A host app can legitimately weaken its own ATS
/// settings for some unrelated legacy API it depends on — this SDK's own upload/config
/// traffic has no reason to inherit that weakening. This matters specifically because this
/// SDK ships into apps it doesn't control (`CONSTITUTION.md` rule #1's whole premise).
public enum SDKOwnedSessionConfiguration {
    public static func make() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return configuration
    }
}
