import Foundation
import Security
import Network
import CryptoKit

// CAVEAT FOR CALLERS (read before adding more tests here or elsewhere that touch Keychain):
//
// `TLSTestIdentityFactory.makeSelfSignedIdentity` persists real key/certificate material into
// the process's default (data-protection) keychain — see the long comment on the identity
// lookup step inside `makeSelfSignedIdentity` for why an isolated, throwaway `SecKeychain`
// turned out not to be viable on this toolchain (confirmed empirically: items added to a
// custom `SecKeychain` via `SecItemAdd` are not retrievable through `SecItemCopyMatching`,
// `SecIdentityCreateWithCertificate`, *or* `kSecClassIdentity` queries against that keychain —
// tried all three). All access within this file is serialized through the target-wide
// `KeychainTestLock` (`Support/KeychainTestLock.swift`) with a short retry, which makes this
// file's own tests reliably green on their own.
//
// That lock is shared, not private to this file, because every test in this file otherwise
// contends for the *same shared keychain* as any other test elsewhere in the target that also
// touches Keychain Services (e.g. `Tests/APMKitTests/Storage/DiskQueueKeyStoreTests.swift`,
// which exercises the real Keychain for SEC-08 key persistence). Swift Testing runs suites in
// parallel by default, and measured empirically on this host: adding this file's tests with only
// a file-private lock raised `KeychainDiskQueueKeyStore`'s pre-existing (already keychain-backed,
// not something this file introduced) round-trip flake rate from never-observed to ~15-30% of
// full-suite runs — the *production* `storeKey` was silently losing the `SecItemAdd` race under
// the added load. Routing both files through one shared `KeychainTestLock` is the actual fix,
// not a workaround — see `KeychainTestLock`'s doc comment.
//
/// A minimal, hand-rolled ASN.1 DER encoder — just enough primitives to build one X.509v3
/// self-signed certificate shape (SEQUENCE, INTEGER, OID, BIT STRING, OCTET STRING,
/// UTF8String/PrintableString, and both context-specific constructed and explicit tags).
/// Deliberately not a general-purpose ASN.1 library: `Package.swift` carries zero test-only
/// dependencies and this keeps it that way (see feat-015 test-infra task).
enum DER {
    /// Length octets per X.690 §8.1.3: short form for <128, long form (0x80 | byteCount)
    /// followed by big-endian length bytes otherwise.
    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    /// Wraps `content` in a tag+length+value triplet.
    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func sequence(_ content: [UInt8]) -> [UInt8] { tlv(0x30, content) }

    /// INTEGER. DER requires a leading 0x00 pad whenever the high bit of the first byte
    /// would otherwise make the value read as negative (two's-complement).
    static func integer(_ bytes: [UInt8]) -> [UInt8] {
        var b = bytes
        if b.isEmpty { b = [0x00] }
        if b[0] & 0x80 != 0 { b.insert(0x00, at: 0) }
        return tlv(0x02, b)
    }

    static func integer(_ value: Int) -> [UInt8] {
        var v = value
        var bytes: [UInt8] = []
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v != 0 && bytes.count < 8
        return integer(bytes)
    }

    /// OID given as dotted components, e.g. [1, 2, 840, 10045, 4, 3, 2].
    static func oid(_ components: [Int]) -> [UInt8] {
        precondition(components.count >= 2)
        var body: [UInt8] = [UInt8(components[0] * 40 + components[1])]
        for c in components.dropFirst(2) {
            var v = c
            var chunk: [UInt8] = [UInt8(v & 0x7F)]
            v >>= 7
            while v > 0 {
                chunk.insert(UInt8(v & 0x7F) | 0x80, at: 0)
                v >>= 7
            }
            body.append(contentsOf: chunk)
        }
        return tlv(0x06, body)
    }

    static func bitString(_ bytes: [UInt8], unusedBits: UInt8 = 0) -> [UInt8] {
        tlv(0x03, [unusedBits] + bytes)
    }

    static func octetString(_ bytes: [UInt8]) -> [UInt8] {
        tlv(0x04, bytes)
    }

    static func null() -> [UInt8] { [0x05, 0x00] }

    static func utf8String(_ s: String) -> [UInt8] { tlv(0x0C, Array(s.utf8)) }

    static func printableString(_ s: String) -> [UInt8] { tlv(0x13, Array(s.utf8)) }

    /// UTCTime, format YYMMDDHHMMSSZ (X.690 §11.8) — sufficient for dates before 2050.
    static func utcTime(_ date: Date) -> [UInt8] {
        let f = DateFormatter()
        f.dateFormat = "yyMMddHHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return tlv(0x17, Array(f.string(from: date).utf8))
    }

    /// Explicit context-specific tag, constructed (used for the certificate `version` field,
    /// tag [0] EXPLICIT).
    static func explicitTag(_ n: UInt8, _ content: [UInt8]) -> [UInt8] {
        tlv(0xA0 | n, content)
    }

    static func boolean(_ value: Bool) -> [UInt8] {
        tlv(0x01, [value ? 0xFF : 0x00])
    }
}

/// Builds and signs a minimal X.509v3 self-signed EC (P-256) certificate, then imports the
/// resulting cert + private key into an ephemeral keychain so `Network.framework` can use it
/// as a `sec_identity_t` for a real TLS handshake. No external tool (`openssl`, bundled fixture
/// files) is used — everything is generated at test-run time via Security.framework +
/// hand-rolled DER encoding.
enum TLSTestIdentityFactory {
    struct GeneratedIdentity {
        let identity: SecIdentity
        let certificate: SecCertificate
        let certificateDER: Data
        /// Keychain items must be removed explicitly — `SecItemAdd`'d keys/certs are not
        /// scoped to the process and will otherwise leak into the user's real keychain
        /// across test runs.
        let cleanup: () -> Void
    }

    enum Error: Swift.Error {
        case keyGenerationFailed(String)
        case signingFailed(String)
        case certificateCreationFailed
        case keychainImportFailed(OSStatus)
        case identityLookupFailed(OSStatus)
    }

    /// EC public key OID: id-ecPublicKey (1.2.840.10045.2.1)
    private static let oidECPublicKey = [1, 2, 840, 10045, 2, 1]
    /// namedCurve prime256v1 / secp256r1 (1.2.840.10045.3.1.7)
    private static let oidPrime256v1 = [1, 2, 840, 10045, 3, 1, 7]
    /// ecdsa-with-SHA256 (1.2.840.10045.4.3.2)
    private static let oidECDSAWithSHA256 = [1, 2, 840, 10045, 4, 3, 2]
    /// commonName (2.5.4.3)
    private static let oidCommonName = [2, 5, 4, 3]

    /// Generates a fresh self-signed identity. Each call produces a distinct key/cert (random
    /// serial + fresh keypair), so a single test run can hold two independent identities —
    /// e.g. to prove pin-mismatch rejection and pin-rotation acceptance.
    /// Serializes every keychain-touching step across concurrent calls via the target-wide
    /// `KeychainTestLock` — not a private lock scoped to this file, because the contention this
    /// avoids isn't limited to calls within this file (see `KeychainTestLock`'s doc comment for
    /// the empirical `DiskQueueKeyStoreTests` flake this caused before the lock was shared).
    static func makeSelfSignedIdentity(
        commonName: String = "localhost",
        notBefore: Date = Date().addingTimeInterval(-3600),
        notAfter: Date = Date().addingTimeInterval(86_400)
    ) throws -> GeneratedIdentity {
        try KeychainTestLock.sync {
            try makeSelfSignedIdentityUnsynchronized(commonName: commonName, notBefore: notBefore, notAfter: notAfter)
        }
    }

    private static func makeSelfSignedIdentityUnsynchronized(
        commonName: String,
        notBefore: Date,
        notAfter: Date
    ) throws -> GeneratedIdentity {
        // 1. Generate an EC P-256 key pair, persisted directly into the process's default
        // "data protection" keychain (the only keychain flavor macOS reliably honors for
        // SecKeyCreateRandomKey since 10.15 — see the long comment at the identity-lookup step
        // below for why the legacy file-based SecKeychain APIs and the `kSecClassIdentity`
        // query were tried first and abandoned). Tagged with a per-call UUID so concurrent test
        // runs can't collide, and so `cleanup()` can remove exactly this key/cert pair without
        // touching anything else in the user's keychain.
        let tag = Data("apmkit-tls-mock-\(UUID().uuidString)".utf8)
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag
            ]
        ]
        var cfError: Unmanaged<CFError>?
        // Retry a couple of times on the intermittent -25300 ("failed to generate CDSA key")
        // race described above — it's transient contention on the legacy keychain backend, not
        // a deterministic failure, and a short retry clears it in practice.
        var privateKey: SecKey?
        for attempt in 0..<3 {
            cfError = nil
            privateKey = SecKeyCreateRandomKey(keyAttrs as CFDictionary, &cfError)
            if privateKey != nil { break }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.05) }
        }
        guard let privateKey else {
            throw Error.keyGenerationFailed(cfError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown")
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw Error.keyGenerationFailed("no public key")
        }
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &cfError) as Data? else {
            throw Error.keyGenerationFailed(cfError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown")
        }
        // SecKeyCopyExternalRepresentation for an EC public key yields the X9.63 uncompressed
        // point (0x04 || X || Y) — exactly what SubjectPublicKeyInfo's BIT STRING wants.
        let publicKeyPoint = [UInt8](publicKeyData)

        // 2. Build TBSCertificate DER.
        let serial = randomSerial()
        let name = distinguishedName(commonName: commonName)
        let tbs = tbsCertificateDER(
            serial: serial,
            issuer: name,
            subject: name,
            notBefore: notBefore,
            notAfter: notAfter,
            subjectPublicKeyPoint: publicKeyPoint
        )

        // 3. Sign the TBSCertificate DER with the private key (ECDSA/SHA256). The signature
        // Security.framework returns is already DER-encoded (SEQUENCE { r INTEGER, s INTEGER }),
        // which is exactly what goes in the outer Certificate's signatureValue BIT STRING.
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, .ecdsaSignatureMessageX962SHA256) else {
            throw Error.signingFailed("ecdsaSignatureMessageX962SHA256 not supported")
        }
        guard let signature = SecKeyCreateSignature(
            privateKey, .ecdsaSignatureMessageX962SHA256, Data(tbs) as CFData, &cfError
        ) as Data? else {
            throw Error.signingFailed(cfError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown")
        }

        // 4. Wrap into the outer Certificate SEQUENCE.
        let signatureAlgorithm = DER.sequence(DER.oid(oidECDSAWithSHA256) + DER.null())
        let certDER = DER.sequence(tbs + signatureAlgorithm + DER.bitString([UInt8](signature)))
        let certData = Data(certDER)

        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw Error.certificateCreationFailed
        }

        // 5. Add the certificate to the same (default, data-protection) keychain as the key.
        // `SecIdentityCreateWithCertificate` / the `kSecClassIdentity` query machinery pairs a
        // certificate with a private key by matching the certificate's public key to a key
        // item already present in the keychain — it does not require them to share a label,
        // only to coexist. We tag the cert item with the same `kSecAttrApplicationTag` purely
        // so `cleanup()` can find and remove both items together.
        let certAddQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: commonName,
            kSecAttrApplicationTag as String: tag
        ]
        var status = SecItemAdd(certAddQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.keychainImportFailed(status) }

        // 6. Look the identity back up. Two earlier approaches were tried and rejected:
        //
        //   a) Importing key + cert into a throwaway *file-based* `SecKeychain` (via
        //      `SecKeychainCreate`) to keep this fully hermetic/ephemeral — unreliable on the
        //      current macOS/Swift toolchain (Swift 6.3, macOS 26 host): `SecKeyCreateRandomKey`
        //      /`SecItemAdd` silently persist to the default "data protection" keychain
        //      regardless of an explicit `kSecUseKeychain` target, and items added to a custom
        //      `SecKeychain` are not findable via `kSecMatchSearchList` even after adding it to
        //      the process's keychain search list (confirmed empirically: `SecItemCopyMatching`
        //      returned `errSecItemNotFound` (-25300) every time).
        //
        //   b) Querying `kSecClassIdentity` directly (with the default data-protection
        //      keychain from (a)'s fallback) — this *found* an identity, but the `SecKey` it
        //      hands back from `SecIdentityCopyPrivateKey` is a legacy CSSM-backed
        //      `SecCDSAKeyRef` that reports itself as RSA regardless of the key's real
        //      (EC) type, and every EC signature attempt against it fails with
        //      `paramErr (-50)`: "algid:sign:ECDSA:... algorithm not supported by the key
        //      <SecCDSAKeyRef ... algorithm id: 1 ...>" (1 == CSSM_ALGID_RSA). That's a real
        //      platform bug/regression in this macOS build's legacy Keychain "Identity"
        //      bridging for EC keys, not a mistake in the DER above — confirmed by generating
        //      an equivalent EC identity via `openssl` + `SecPKCS12Import`, which handshakes
        //      fine, and by directly querying `kSecClassKey` (not `kSecClassIdentity`) for the
        //      same key, which also comes back correctly typed and signs fine.
        //
        // The fix: `SecIdentityCreateWithCertificate` takes a different code path than the
        // `kSecClassIdentity` item query and correctly pairs the certificate with the *modern*
        // EC `SecKey` already sitting in the default keychain from step 1 — empirically
        // verified to sign successfully. (macOS-only API — fine here since this file is host
        // test-infrastructure, never shipped to iOS.)
        var identityRef: SecIdentity?
        status = SecIdentityCreateWithCertificate(nil, certificate, &identityRef)
        guard status == errSecSuccess, let identity = identityRef else {
            throw Error.identityLookupFailed(status)
        }

        let cleanup: () -> Void = {
            SecItemDelete([kSecClass as String: kSecClassCertificate, kSecAttrApplicationTag as String: tag] as CFDictionary)
            SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag] as CFDictionary)
        }

        return GeneratedIdentity(
            identity: identity,
            certificate: certificate,
            certificateDER: certData,
            cleanup: cleanup
        )
    }

    // MARK: - DER construction helpers

    private static func randomSerial() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // Ensure it reads as positive and non-zero-leading for a cleaner INTEGER encoding;
        // DER.integer() will still pad correctly regardless.
        bytes[0] &= 0x7F
        if bytes.allSatisfy({ $0 == 0 }) { bytes[0] = 0x01 }
        return bytes
    }

    /// RDNSequence with a single commonName attribute — enough for a test-only self-signed cert.
    private static func distinguishedName(commonName: String) -> [UInt8] {
        let attribute = DER.sequence(DER.oid(oidCommonName) + DER.utf8String(commonName))
        let rdn = DER.tlv(0x31, attribute) // SET OF
        return DER.sequence(rdn)
    }

    /// basicConstraints (2.5.29.19)
    private static let oidBasicConstraints = [2, 5, 29, 19]
    /// subjectKeyIdentifier (2.5.29.14)
    private static let oidSubjectKeyIdentifier = [2, 5, 29, 14]

    private static func tbsCertificateDER(
        serial: [UInt8],
        issuer: [UInt8],
        subject: [UInt8],
        notBefore: Date,
        notAfter: Date,
        subjectPublicKeyPoint: [UInt8]
    ) -> [UInt8] {
        let version = DER.explicitTag(0, DER.integer(2)) // v3
        let serialInt = DER.integer(serial)
        let signatureAlgorithm = DER.sequence(DER.oid(oidECDSAWithSHA256) + DER.null())
        let validity = DER.sequence(DER.utcTime(notBefore) + DER.utcTime(notAfter))
        let algIdentifier = DER.sequence(DER.oid(oidECPublicKey) + DER.oid(oidPrime256v1))
        let subjectPublicKeyInfo = DER.sequence(algIdentifier + DER.bitString(subjectPublicKeyPoint))

        // Network.framework's TLS stack (coretls) declines to use a locally-configured server
        // identity that lacks X.509v3 extensions — a bare v3 cert with no `extensions` field
        // parses fine via `SecCertificateCreateWithData` (it's valid per X.690) but the TLS
        // handshake then simply stalls forever in `.preparing` with no `.failed` state,
        // confirmed empirically by diffing this cert's DER against one openssl produces (which
        // always includes Basic Constraints + Subject/Authority Key Identifier) and by testing
        // that identical listener code *does* complete a handshake once those extensions are
        // present. Basic Constraints (critical, CA:TRUE — mirroring what `openssl req -x509`
        // produces by default for a self-signed cert, which is the configuration verified to
        // make the handshake succeed) and Subject Key Identifier (RFC 5280 method 1: SHA-1 of
        // the raw public key bits) are the minimum that made the handshake succeed.
        let subjectKeyIdentifier = Insecure.SHA1.hash(data: Data(subjectPublicKeyPoint))
        let basicConstraintsExt = DER.sequence(
            DER.oid(oidBasicConstraints) + DER.boolean(true) + DER.octetString(DER.sequence([]))
        )
        let subjectKeyIdentifierExt = DER.sequence(
            DER.oid(oidSubjectKeyIdentifier) + DER.octetString(DER.octetString([UInt8](subjectKeyIdentifier)))
        )
        let extensions = DER.explicitTag(3, DER.sequence(basicConstraintsExt + subjectKeyIdentifierExt))

        let tbsContent = version + serialInt + signatureAlgorithm + issuer + validity + subject
            + subjectPublicKeyInfo + extensions
        return DER.sequence(tbsContent)
    }
}

/// A loopback-only TLS-terminating listener built on `Network.framework`. Accepts a single
/// connection, completes a real TLS handshake against the `sec_identity_t` it was configured
/// with, then writes a canned HTTP/1.1 response — enough for a test to drive a genuine
/// `URLSession` HTTPS request through a real handshake (feat-015 certificate pinning tests).
final class TLSMockServer {
    enum ServerError: Swift.Error {
        case notReady
        case listenerFailed(String)
    }

    private let identity: SecIdentity
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "tls-mock-server")
    private var connections: [NWConnection] = []
    /// Response bytes written after a successful handshake. Defaults to a minimal canned
    /// HTTP/1.1 202 — override for tests that need to inspect the request body first.
    var responseBytes: Data = Data("HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)

    init(identity: SecIdentity) {
        self.identity = identity
    }

    /// Starts the listener bound to an ephemeral loopback port and returns that port once
    /// bound. Synchronous from the caller's point of view (blocks briefly on a semaphore) so
    /// call sites don't need to thread async/await through XCTest/Swift Testing setup.
    @discardableResult
    func start() throws -> UInt16 {
        let secIdentity = sec_identity_create(identity)!
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)
        // Test-only pinning target: allow the full TLS 1.2+ range so the harness isn't
        // coupled to whatever floor CONSTITUTION.md's TLS-floor feature (feat-011) mandates in
        // production code — the *client* under test is what enforces/pins, not this fixture.
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)

        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw ServerError.listenerFailed(String(describing: error))
        }
        self.listener = listener

        let ready = DispatchSemaphore(value: 0)
        var boundPort: UInt16 = 0
        var startError: Swift.Error?

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if case let .hostPort(_, port) = listener.parameters.requiredLocalEndpoint ?? .hostPort(host: "127.0.0.1", port: 0) {
                    boundPort = port.rawValue
                }
                // requiredLocalEndpoint doesn't reflect the OS-assigned ephemeral port; read
                // it from the listener itself once bound.
                if let actual = listener.port { boundPort = actual.rawValue }
                ready.signal()
            case .failed(let error):
                startError = ServerError.listenerFailed(String(describing: error))
                ready.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)

        _ = ready.wait(timeout: .now() + 5)
        if let startError { throw startError }
        guard boundPort != 0 else { throw ServerError.notReady }
        return boundPort
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections { connection.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.readRequest(on: connection)
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// Reads until the header terminator and, if `Content-Length` is present, until that many
    /// body bytes have arrived — same reasoning as `MockHTTPServer.readRequest`: a POST body
    /// (feat-015's pinning tests exercise real `IngestClient` uploads, not just bare `GET`s)
    /// routinely arrives across more than one `receive` call, and responding + closing the
    /// connection after only the first fragment races the client still writing its body,
    /// surfacing as a spurious connection-reset on the client side that has nothing to do with
    /// the TLS/pinning behavior actually under test. Content is otherwise unparsed/unused —
    /// this fixture only needs to prove the handshake completed and return a canned response.
    private func readRequest(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil else { return }

            var buffer = buffer
            if let data { buffer.append(data) }

            let terminator = Data("\r\n\r\n".utf8)
            guard let headerEnd = buffer.range(of: terminator) else {
                self.readRequest(on: connection, buffer: buffer)
                return
            }

            let headerText = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
            let contentLength = headerText
                .components(separatedBy: "\r\n")
                .compactMap { line -> Int? in
                    guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "content-length" else { return nil }
                    return Int(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
                }
                .first ?? 0

            let bodySoFar = buffer.count - headerEnd.upperBound
            guard bodySoFar >= contentLength else {
                self.readRequest(on: connection, buffer: buffer)
                return
            }

            let response = self.responseBytes
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
