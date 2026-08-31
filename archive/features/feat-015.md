# feat-015 · Optional Certificate Pinning (opt-in, P2)

- **Status:** ✅ done · closed 2026-08-31 · **Depends on:** feat-011 (TLS floor), feat-010
  (`RemoteConfigStore` — the kill switch)
- **Requirements (SEC-11, P2, per the 2026-08-29 docs/02 §6.3 decision):** off by default;
  backup pin + kill switch mandatory together whenever enabled; kill switch never drops below
  feat-011's verified TLS floor (SEC-12 applies identically pinned, off, or killed).
- **Done when (all met):**
  1. Pinning OFF (default) behaves identically to feat-011 — zero pinning code path active.
  2. Pinning ON rejects a real wrong-certificate handshake and fails closed.
  3. A simulated certificate rotation continues working via the backup pin, no config change.
  4. The `disabledFeatures` kill switch disables pinning specifically (still verified, not
     unverified) and re-enables it on the next request, no restart needed.

## What was built

**Production (`Sources/APMKit/Sync/`):**
- `CertificatePinningConfiguration.swift` — a pin is the SHA-256 hash of a certificate's raw
  DER bytes (`SecCertificateCopyData`), not the certificate's public key (SPKI). See
  "Decision: full-certificate pinning, not SPKI" below for why. The failable `init?` is the
  backup-pin enforcement mechanism: it is structurally impossible to construct a config with no
  backup pin distinct from the primary — same "make forgetting impossible" shape as
  feat-005/009, not integrator discipline.
- `CertificatePinning` (same file) — bundles `CertificatePinningConfiguration` with the
  `RemoteConfigStore` that carries its kill switch, so `IngestClient`/`RemoteConfigFetcher`
  take one parameter, not two independent optionals a caller could pass out of sync (pinning
  set, store forgotten, silently unpinned).
- `CertificatePinningValidator.swift` — pure pin-matching logic (`SecTrust` + `Set<Data>` →
  `Bool`), checks every certificate in the presented chain (not just the leaf) so a pin can
  target an intermediate. Kept separate from the delegate so it's unit-testable against a real
  `SecTrust` built with `SecTrustCreateWithCertificates`, no live socket needed.
- `PinningSessionDelegate.swift` — the `URLSessionDelegate`. Reads
  `remoteConfigStore.current.disabledFeatures` on every challenge (not cached at init) so the
  kill switch takes effect on the next connection with no restart. Kill switch ON or no pin
  match → `.performDefaultHandling` (feat-011's plain TLS floor, full system CA validation) or
  `.cancelAuthenticationChallenge` respectively — never a silent accept.
- `IngestClient`/`RemoteConfigFetcher` — new optional `pinning: CertificatePinning? = nil`
  parameter. `nil` (default): session built exactly as feat-011 left it, no delegate — the
  `session.delegate == nil` assertion MOB-09's anti-loop test already makes is preserved
  byte-for-byte. Non-nil: session built with `PinningSessionDelegate`. An explicit `session:`
  parameter (as tests that supply their own already do) takes priority over `pinning` — passing
  both together silently drops pinning, a real bug this feature's own early test-writing hit
  and fixed (see "Bugs found" below), documented in both inits' doc comments now.

**Test infrastructure (`Tests/APMKitTests/Support/`), built from scratch — none of it existed
before this feature:**
- `TLSMockServer.swift` — a real loopback TLS-terminating listener (`Network.framework`,
  `NWListener` + `NWProtocolTLS.Options`) and `TLSTestIdentityFactory`, which hand-encodes a
  minimal X.509v3 self-signed EC P-256 certificate's DER bytes (a small hand-rolled ASN.1
  encoder — `Package.swift` carries zero test-only dependencies and this keeps it that way),
  signs it with `SecKeyCreateSignature`, and produces a real `SecIdentity` via
  `SecIdentityCreateWithCertificate`. No external tool (`openssl`, bundled fixtures) — generated
  at test-run time. This is what makes feat-015's tests **real TLS handshakes against real,
  varying certificates**, not the generic "handshake fails for any reason" trick feat-011 used
  (its archive note explicitly flagged that gap for whenever pinning needed real cert content).
- `TLSMockServerTests.swift` — sanity tests proving the fixture itself does a genuine handshake
  and its certificate DER round-trips through `SecCertificateCreateWithData`.
- `KeychainTestLock.swift` — see "Bugs found," below.

**Tests (`Tests/APMKitTests/Sync/`):**
- `CertificatePinningConfigurationTests.swift` — backup-pin enforcement (empty backups,
  duplicate-only backups both fail construction), pin hashing.
- `CertificatePinningValidatorTests.swift` — pure logic against real certs, no live socket.
- `CertificatePinningTests.swift` — the "Done when" tests, each mapped 1:1 to a criterion above,
  driven through the real `IngestClient`/`RemoteConfigFetcher`/`RemoteConfigStore` types and a
  live `TLSMockServer`, not fakes:
  - OFF: `session.delegate == nil` for both client types.
  - ON, wrong cert: real handshake, real rejection, `!= .accepted`.
  - ON, matching cert: real handshake, real `.accepted`.
  - Rotation: pin config carries the *next* cert's hash as backup in advance; server already
    presents that cert; succeeds with zero config change at the moment of rotation.
  - Kill switch ON: the self-signed cert that *would* match the pin is rejected by ordinary
    system CA trust once pinning is off — proof the fallback is feat-011's verified floor, not
    an unverified connection (SEC-12).
  - Kill switch flipped back off on the same live `RemoteConfigStore`, no new client
    construction: pinning re-engages on the very next request.
  - One `RemoteConfigFetcher` test confirming the same delegate/session wiring works for
    `GET /v1/config`, not just `IngestClient` — not a full duplicate suite, since both types
    share the identical delegate.

214 tests (was 196 at feat-014 close; +18: 3 `TLSMockServer` sanity + 15 feat-015 behavioral).
`./verify.sh build`/`test`/`budget` all `HARNESS_VERIFY: PASS`; `test` re-run 12× clean after
the flake fix below (see "Bugs found"). `podspec` not re-run — no dependency or podspec
`source_files` glob change (new files land under the existing `Sources/APMKit/**/*.swift`
pattern feat-013 already covers).

## Decision: full-certificate pinning, not SPKI public-key pinning

A pin here is SHA-256 of the whole certificate's DER bytes, not the industry-common
"pin the SubjectPublicKeyInfo" (SPKI) approach that survives a same-key cert renewal without
any pin update. Two reasons this SDK doesn't need that:

1. **Extracting a comparable SPKI hash from `SecKeyCopyExternalRepresentation`'s raw key bytes
   requires reconstructing the DER `SubjectPublicKeyInfo` wrapper by hand per key
   type/curve/size** (TrustKit's approach: hardcoded ASN.1 header tables keyed by algorithm).
   Full-certificate hashing needs none of that — `SecCertificateCopyData` already returns
   exactly the bytes to hash.
2. **SEC-11's own design already assumes pins get updated for rotation, not survived
   automatically** — that's the entire reason a backup pin is mandatory (docs/02 §6.3: a
   rotation with no matching pin blinds telemetry until an app release). An ops team planning a
   cert rotation already needs to know the next cert's hash in advance either way; whether that
   hash is "of the cert" or "of the key" costs the same operational step.

Trade-off, stated for the record: a same-key certificate renewal (new cert, same key pair) that
an SPKI-pinned client would accept transparently still requires this SDK's pins to be updated —
functionally identical to any other rotation from this SDK's point of view. Acceptable given
(1) and (2): this SDK controls both ends of the pinned connection, so the operational step is
already in place regardless.

## Bugs found and fixed during this feature (not pre-existing, both introduced by this feature's own work)

1. **`TLSMockServer`'s original single-`receive()` response handler raced multi-segment request
   bodies.** Responding and closing the connection after the *first* byte of a real `POST`
   (`IngestClient`'s gzip body routinely arrives split across TCP segments) closed the
   connection before the client finished writing, surfacing as a spurious client-side
   connection-reset that looked like a pinning failure but had nothing to do with pin logic.
   Fixed by making `TLSMockServer.readRequest` buffer until the header terminator and
   `Content-Length` bytes have fully arrived — the same technique `MockHTTPServer` already uses
   — before responding.
2. **Passing both `pinning:` and an explicit `session:` to `IngestClient`/`RemoteConfigFetcher`
   silently drops pinning** (explicit `session` wins by design, since a caller supplying their
   own session already owns its delegate) — this feature's own first draft of
   `CertificatePinningTests.swift` did exactly that (passing a short-timeout session alongside
   `pinning:`), making every "should succeed" test fail while every "should fail" test passed
   trivially for the wrong reason. Not a production bug — the inits' behavior is correct and
   is now documented explicitly in both doc comments — but real enough to have shipped a
   false-negative test suite if it had gone unnoticed. Fixed by removing the redundant
   `session:` argument from the pinning tests; the default init already builds the correctly
   pinned session.
3. **Adding real-Keychain-backed TLS test infrastructure introduced flaky failures in
   feat-014's pre-existing `DiskQueueKeyStoreTests`** (`KeychainDiskQueueKeyStore`'s SEC-08
   round-trip test), observed at roughly 15-30% of full `swift test` runs. Root cause, traced to
   actual production code: `KeychainDiskQueueKeyStore.storeKey`
   (`Sources/APMKit/Storage/DiskQueueKeyStore.swift:73`) silently loses the `SecItemAdd` race
   under Swift Testing's parallel execution once enough concurrent Keychain load exists in the
   process — the write fails, the store falls back to an in-memory-only key, and a second store
   instance reading the same service/account generates a *different* key, failing the
   round-trip assertion. This is a latent property of the shared-keychain design that
   `TLSTestIdentityFactory`'s added Keychain traffic was simply the first thing in this repo to
   surface. Fixed with `Tests/APMKitTests/Support/KeychainTestLock.swift`, a target-wide
   serialization lock, applied both in `TLSTestIdentityFactory` and (necessarily, to actually
   close the race) in `DiskQueueKeyStoreTests.swift` itself — confirmed clean across 12
   consecutive full-suite runs after the fix, versus 2 failures in 5 runs before it. Not
   production code changed, not `KeychainDiskQueueKeyStore`'s at-rest-encryption behavior
   affected — this is test-process-only contention that only exists because `swift test` and
   the app's real Keychain-backed store now share one process's Keychain Services calls, which
   a real device install never encounters.

## Explicitly not done here

- No composition-root wiring — `APM.start`'s pinning config surface is feat-016's job
  (`FEATURES.md`'s own ordering note: composition root deliberately comes *after* feat-015 so
  it wires already-built pieces rather than being patched afterward). This feature's pinning
  types are usable standalone by any caller constructing `IngestClient`/`RemoteConfigFetcher`
  directly, same as every other pre-feat-016 type in this SDK.
- No change to `APM.instrumentedSession()` — SEC-11's scope is the SDK's own ingestion
  connection only, per docs/02 §6.3's decision box; the host app's own API traffic pinning is
  observed, never performed, by this SDK (`NetworkCaptureForwardingDelegate`, unchanged).

**Files added:** `Sources/APMKit/Sync/CertificatePinningConfiguration.swift`,
`Sources/APMKit/Sync/CertificatePinningValidator.swift`,
`Sources/APMKit/Sync/PinningSessionDelegate.swift`,
`Tests/APMKitTests/Support/TLSMockServer.swift`,
`Tests/APMKitTests/Support/TLSMockServerTests.swift`,
`Tests/APMKitTests/Support/KeychainTestLock.swift`,
`Tests/APMKitTests/Sync/CertificatePinningConfigurationTests.swift`,
`Tests/APMKitTests/Sync/CertificatePinningValidatorTests.swift`,
`Tests/APMKitTests/Sync/CertificatePinningTests.swift`.
**Files amended:** `Sources/APMKit/Sync/IngestClient.swift`,
`Sources/APMKit/Stability/RemoteConfigFetcher.swift`,
`Tests/APMKitTests/Storage/DiskQueueKeyStoreTests.swift` (keychain-lock fix only, no assertion
changes).
