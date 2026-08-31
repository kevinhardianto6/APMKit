# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Pre-Pilot Hardening epic (3/5) — remediating P0/P1/P2 gaps the shipped APM
  Kit iOS SDK epic left unfiled, before the Android port starts.
- **Active feature:** none — feat-013 (Distribution: CocoaPods + semver) closed ✅. feat-014
  (At-Rest Queue Encryption, SEC-08) is next per the epic's fixed order, not started.
- **Status:** —
- **Last verify:** `./verify.sh all` → `HARNESS_VERIFY: PASS (all)`, 2026-08-30. 186 tests,
  plus `budget` (binary-size delta ~360KB) and the new `podspec` check (`pod lib lint` passes).

## Next step

feat-013 closed 2026-08-30 — full detail rotated to `archive/features/feat-013.md`. All three
of the user's explicit checkpoints covered:
1. SPM external resolution verified with **real git+tag mechanics** (a bare clone tagged
   `1.0.0`, a separate consumer package fetching it via `file://` URL, not a local path
   dependency) — built and ran, printed the real linked `SDKInfo.current.version`.
2. `APMKit.podspec` added, depending on `KSCrash/Recording` (matching SPM's product exactly).
   **Found and fixed a real bug**, not assumed compatible: `pod lib lint` initially failed —
   CocoaPods' `KSCrash` pod exposes one umbrella module (`import KSCrash`), not per-subspec
   modules like SPM (`import KSCrashRecording`). Every KSCrash-touching file now imports
   conditionally on `canImport(KSCrashRecording)`. Lints clean now.
3. `VERSIONING.md` (MOB-24) — semver policy, current version 1.0.0, and a
   `VersioningTests.swift` test locking `SDKInfo.current.version`/`APMKit.podspec`'s
   `s.version` in sync (verified it actually catches drift, not just passes trivially).

**Flagged per the user's explicit ask, not fixed (out of scope):** the SDK has no composition
root — a from-scratch integration needs ~a dozen manually-wired pieces before the first event
is captured. Real risk to MOB-25's "under 30 minutes" target. Written up in `VERSIONING.md` →
"Integration friction" for whoever scopes that work next — not something to silently build
here.

Session history before feat-013 (feat-010/011/012, the epic's filing/re-scope) is in
`archive/sessions/2026-08-29-feat-010-011-and-hardening-epic.md`. The 5 unverified Phase 1
manual-checklist items stay open — don't close them synthetically. Android port starts only
after this epic closes.

## Parked

- **Android port** — sequenced *after* this epic. Parity notes:
  `archive/epics/phase-1-2-wrap-up.md` → "What an Android port would need for parity."
- **Composition root** (`APM.start(configuration:)` or similar) — flagged this session as a
  real MOB-25 risk, not yet scoped as its own feature. Raise with the user before MOB-25's
  sample app/integration docs get written.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `APMKit.podspec` | Added | feat-013, MOB-23 — depends on `KSCrash/Recording` matching SPM |
| `Sources/APMKit/APMKit.swift`, `Crash/{CrashReporter,CrashReportSource,CrashUserInfoStore}.swift`, `Stability/HangObserving.swift` | `import KSCrashRecording` → conditional on `canImport` | Real CocoaPods/SPM module-name mismatch found via `pod lib lint`, not assumed |
| `VERSIONING.md` | Added | feat-013, MOB-24 — semver policy, two-manifest-sync risk, integration-friction writeup |
| `Tests/APMKitTests/VersioningTests.swift` | Added | Locks `SDKInfo`/podspec version parity |
| `verify.sh` | +`podspec` mode, included in `all` | feat-013 |
| `AGENTS.md` | Verification section documents `podspec` | feat-013 |
| `FEATURES.md` | feat-013 → ✅, detail rotated to archive, epic progress 3/5, composition-root finding called out at epic level | Feature closed |
| `archive/features/feat-013.md` | Added — full detail | Rotation |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
