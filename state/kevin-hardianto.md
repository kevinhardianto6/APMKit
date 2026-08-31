# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Pre-Pilot Hardening epic (4/6) — remediating P0/P1/P2 gaps the shipped APM
  Kit iOS SDK epic left unfiled, before the Android port starts.
- **Active feature:** none — feat-015 (Optional Certificate Pinning, SEC-11) closed ✅. feat-016
  (Composition Root) is next per the epic's fixed order, not started.
- **Status:** —
- **Last verify:** `./verify.sh build`/`test`/`budget` → all PASS, 2026-08-31. 214 tests.

## Next step

feat-015 closed — full detail, including two real bugs found in this session's own new test
infra (a `TLSMockServer` request-race and a keychain-contention flake introduced into
feat-014's pre-existing `DiskQueueKeyStoreTests`, both fixed) and the full-cert-vs-SPKI pinning
decision, is in `archive/features/feat-015.md`. Built from scratch: real TLS test
infrastructure (`Tests/APMKitTests/Support/TLSMockServer.swift`) — nothing in this repo could
drive a genuine TLS handshake before this feature; feat-011 had explicitly worked around that
gap and flagged it as a known limitation for whenever pinning needed real cert content.

Next up: **feat-016 (Composition Root, `APM.start`)**, per the fixed order — depends on feat-014
and feat-015, both now ✅, so it's ready. Per `CONSTITUTION.md`'s build order, this is a stop-
for-review point: do not start feat-016 in the same sitting as feat-015 without the user's go-
ahead. feat-016's scope already includes the internal verification app spike (see its
`FEATURES.md` entry) — start there per its own "spike before building on it" instruction.

Session history through feat-013 is in
`archive/sessions/2026-08-30-feat-012-013-and-composition-root-decision.md`. The 5 unverified
Phase 1 manual-checklist items (plus 8, 9) stay open. Android port starts only after this
epic closes.

## Parked

- **Android port** — sequenced *after* this epic. Parity notes:
  `archive/epics/phase-1-2-wrap-up.md` → "What an Android port would need for parity."

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session, since feat-014's commit)

| File | Change | Why |
|------|--------|-----|
| `FEATURES.md` | feat-016 entry expanded: internal verification app added to its scope; feat-015 marked ✅, detail rotated to archive; epic progress 4/6 → 5/6 | User-directed re-scope, then feat-015 close |
| `Sources/APMKit/Sync/CertificatePinningConfiguration.swift` | new: pin type + `CertificatePinning` bundle | feat-015 |
| `Sources/APMKit/Sync/CertificatePinningValidator.swift` | new: pure pin-match logic | feat-015 |
| `Sources/APMKit/Sync/PinningSessionDelegate.swift` | new: `URLSessionDelegate`, kill-switch aware | feat-015 |
| `Sources/APMKit/Sync/IngestClient.swift` | optional `pinning:` param, session-build branch | feat-015 |
| `Sources/APMKit/Stability/RemoteConfigFetcher.swift` | same `pinning:` param as `IngestClient` | feat-015 |
| `Tests/APMKitTests/Support/TLSMockServer.swift` | new: real self-signed-cert TLS test server (no prior TLS test infra existed) | feat-015 |
| `Tests/APMKitTests/Support/TLSMockServerTests.swift` | new: sanity tests for the fixture itself | feat-015 |
| `Tests/APMKitTests/Support/KeychainTestLock.swift` | new: shared keychain-serialization lock | feat-015 (fixes a flake this session's own test infra introduced) |
| `Tests/APMKitTests/Storage/DiskQueueKeyStoreTests.swift` | wrapped keychain calls in `KeychainTestLock` | feat-015 flake fix, no assertion changes |
| `Tests/APMKitTests/Sync/CertificatePinningConfigurationTests.swift` | new | feat-015 |
| `Tests/APMKitTests/Sync/CertificatePinningValidatorTests.swift` | new | feat-015 |
| `Tests/APMKitTests/Sync/CertificatePinningTests.swift` | new: the "Done when" tests | feat-015 |
| `archive/features/feat-015.md` | new: full feature detail, rotated per closure | feat-015 close |

Prior changes this session (feat-014 itself) are committed — see commit `3939eaa` and
`archive/features/feat-014.md` for that detail, not repeated here. **feat-015's changes above
are not yet committed** — its own commit is a separate step (`git commit`, not done by this
agent per `CONSTITUTION.md`'s "never auto-commit").

_Ground truth: run `git diff --stat` to confirm this table matches reality._
