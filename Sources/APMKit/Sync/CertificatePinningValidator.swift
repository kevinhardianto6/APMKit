import Foundation
import Security

/// Pure pin-matching logic, kept separate from `PinningSessionDelegate` so it's testable
/// directly against a real `SecTrust` (e.g. one built with `SecTrustCreateWithCertificates`
/// from real certificate data) without needing a live socket.
enum CertificatePinningValidator {
    /// `true` if any certificate in `trust`'s presented chain hashes to one of `pins`.
    /// Checking the whole chain (not just the leaf) means a pin can target an intermediate —
    /// useful for a planned rotation where the backup pin is the *next* leaf's known-in-advance
    /// issuing intermediate rather than the leaf itself.
    ///
    /// Defensive per `CONSTITUTION.md` rule #1: an empty or unreadable chain is never trusted
    /// — it returns `false`, the fail-closed default, rather than throwing.
    static func matches(trust: SecTrust, pins: Set<Data>) -> Bool {
        guard !pins.isEmpty else { return false }
        let chain = certificateChain(of: trust)
        guard !chain.isEmpty else { return false }
        for certificate in chain {
            let der = SecCertificateCopyData(certificate) as Data
            if pins.contains(CertificatePinningConfiguration.pin(forCertificateDER: der)) {
                return true
            }
        }
        return false
    }

    private static func certificateChain(of trust: SecTrust) -> [SecCertificate] {
        if #available(iOS 15.0, macOS 12.0, *) {
            return (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        }
        // Pre-iOS-15 API, kept only so this compiles against older host toolchains; the SDK's
        // own floor is iOS 15 (CONSTITUTION.md), so this branch is unreachable in practice.
        let count = SecTrustGetCertificateCount(trust)
        return (0..<count).compactMap { SecTrustGetCertificateAtIndex(trust, $0) }
    }
}
