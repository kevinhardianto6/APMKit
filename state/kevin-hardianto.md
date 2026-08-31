# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Pre-Pilot Hardening epic (4/6) — remediating P0/P1/P2 gaps the shipped APM
  Kit iOS SDK epic left unfiled, before the Android port starts.
- **Active feature:** none — feat-014 (At-Rest Queue Encryption, SEC-08) closed ✅. feat-015
  (Optional Certificate Pinning, opt-in P2) is next per the epic's fixed order, not started.
- **Status:** —
- **Last verify:** `./verify.sh build`/`test` → both PASS, 2026-08-31. 196 tests.

## Next step

feat-014 closed 2026-08-31 — full detail in `archive/features/feat-014.md`. AES-GCM on
`FileDiskQueue`, key in Keychain, **real by default** (no composition root needed to opt in).
Proven for real: macOS Keychain round-trip, real AES-GCM round-trip, real on-disk-bytes
inspection (not plaintext), real Simulator write. **Not proven, added as checklist item 9:**
true cross-app-relaunch Keychain persistence — `xcodebuild test` resets Keychain state between
invocations regardless of app-binary identity (root-caused via `simctl spawn log show`), so
the feat-009-style two-phase harness technique doesn't transfer here. Needs a real installed
app to verify for real, which this repo doesn't have — same wall as feat-012's cold-start
reasoning and feat-013's composition-root finding.

Also fixed two **pre-existing** iOS-15-floor violations only a real Simulator build caught
(macOS `swift test` doesn't enforce the same availability table): `Data.contains` (iOS 16+,
in new test helpers) and Swift `Regex`/`firstMatch(of:)` (iOS 16+, in already-committed
feat-013's `VersioningTests.swift` — a real bug in shipped work, not new).

**Not yet committed** — see `git status` before starting feat-015. Session history through
feat-013 is in `archive/sessions/2026-08-30-feat-012-013-and-composition-root-decision.md`.
The 5 unverified Phase 1 manual-checklist items (plus now 8, 9) stay open. Android port starts
only after this epic closes.

## Parked

- **Android port** — sequenced *after* this epic. Parity notes:
  `archive/epics/phase-1-2-wrap-up.md` → "What an Android port would need for parity."

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `FEATURES.md` | feat-016 (Composition Root) filed at user's direction after feat-013 review | New feature, scheduled before the pilot |
| `Sources/APMKit/Storage/{DiskQueueKeyStore,DiskQueueEncryption}.swift` | Added | feat-014, SEC-08 |
| `Sources/APMKit/Storage/FileDiskQueue.swift` | Encryption wired (real by default); `peek()` skips poison files instead of aborting the batch | feat-014 |
| `Tests/APMKitTests/Storage/{DiskQueueKeyStoreTests,DiskQueueEncryptionTests,IOSDiskEncryptionHarnessTests}.swift` | Added | feat-014 evidence |
| `Tests/APMKitTests/Support/DataContainsHelper.swift` | Added | iOS-15-compatible `Data` substring search (found via real Simulator build) |
| `Tests/APMKitTests/{BreadcrumbLeakTests,PipelineEndToEndTests,UserIdentityLeakTests,Scrubbing/ScrubberTests}.swift` | `FileDiskQueue(..., encryption: nil)` | These test pre-encryption scrubbing, not encryption |
| `Tests/APMKitTests/VersioningTests.swift` | Regex → NSRegularExpression | Real pre-existing iOS-15-floor bug, found via feat-014's Simulator build |
| `FEATURES.md` | feat-014 → ✅, detail rotated, epic progress 4/6, checklist item 9 added | Feature closed |
| `archive/features/feat-014.md` | Added — full detail incl. the Keychain-tooling finding | Rotation |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
