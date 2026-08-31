import Foundation
import CryptoKit

/// SEC-11: per-app, opt-in configuration for pinning the SDK's own ingestion connection
/// (`IngestClient`/`RemoteConfigFetcher`) — never the host app's own API traffic, which is
/// out of scope (docs/02 §6.3's decision box: "SDK hanya mengamati" the host's own pinning via
/// `NetworkCaptureForwardingDelegate`, it never performs pinning on that connection itself).
///
/// A pin is the SHA-256 hash of a certificate's raw DER bytes (`SecCertificateCopyData`) — any
/// certificate in the presented chain matching a configured pin is trusted for that connection.
/// This SDK controls both ends of the pinned connection (its own ingestion endpoint), so pin
/// match *is* the trust decision for a pinned connection — there is no separate system-CA
/// check layered on top. That is also why a rotation with no matching pin has no fallback:
/// SEC-11 requires a **backup pin** for exactly this reason, enforced structurally below rather
/// than left to integrator discipline (same "make forgetting impossible" shape as feat-005/009).
///
/// The failable `init` is the enforcement mechanism: it is not possible to construct a
/// `CertificatePinningConfiguration` without at least one backup pin distinct from the primary.
public struct CertificatePinningConfiguration: Equatable {
    public let primaryPin: Data
    public let backupPins: [Data]

    /// All pins this connection accepts — what `PinningSessionDelegate` actually checks
    /// against. A `Set` because match is membership, not order.
    public var acceptedPins: Set<Data> { Set(backupPins + [primaryPin]) }

    /// `nil` if `backupPins` is empty, or contains only duplicates of `primaryPin` — either
    /// way, that is not a backup, and SEC-11 says pinning must never be enabled without one.
    public init?(primaryPin: Data, backupPins: [Data]) {
        guard backupPins.contains(where: { $0 != primaryPin }) else { return nil }
        self.primaryPin = primaryPin
        self.backupPins = backupPins
    }

    /// SHA-256 over a certificate's raw DER bytes — what a pin actually is. Exposed so host
    /// apps (and tests) can compute a pin from a `SecCertificate` without reimplementing the
    /// hash themselves.
    public static func pin(forCertificateDER der: Data) -> Data {
        Data(SHA256.hash(data: der))
    }
}

/// Bundles the pin material with the `RemoteConfigStore` that carries its kill switch — SEC-11
/// requires the two together whenever pinning is enabled, so they're one type instead of two
/// independent optional parameters a caller could pass out of sync (pinning set, store
/// forgotten, silently unpinned). `IngestClient`/`RemoteConfigFetcher` take this single type,
/// not `(CertificatePinningConfiguration?, RemoteConfigStore?)`.
public struct CertificatePinning {
    public let configuration: CertificatePinningConfiguration
    public let remoteConfigStore: RemoteConfigStore

    public init(configuration: CertificatePinningConfiguration, remoteConfigStore: RemoteConfigStore) {
        self.configuration = configuration
        self.remoteConfigStore = remoteConfigStore
    }
}
