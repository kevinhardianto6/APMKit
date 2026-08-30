# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Was Phase 1+2 of the APM Kit iOS SDK (shipped 2026-08-29, 10/10 features).
  Now: **Pre-Pilot Hardening** epic (0/5), re-scoped 2026-08-29 after the user's SEC-11
  decision (see below), before the Android port starts.
- **Active feature:** none yet — feat-011 (TLS Floor + Fail-Closed) is next up, not started.
- **Status:** —
- **Last verify:** `./verify.sh build` and `./verify.sh test` → both `HARNESS_VERIFY: PASS`,
  2026-08-29. 178 tests — unchanged this session (planning/scoping only, no code touched).

## Next step

**Re-scope, same day as filing:** the user recorded a real decision in `docs/02-Mobile-SDK.md`
§6.3 — SEC-11 (cert pinning on the SDK's own ingest connection) demoted P1 → **P2, opt-in, off
by default**. Reasoning: mandatory pinning risks silently killing telemetry app-wide on a cert
rotation (an app-release-cycle recovery), for a threat that only matters once an attacker can
already plant a CA on-device. SEC-10 (TLS 1.2+) and SEC-12 (fail-closed, applies regardless of
pinning) stay P0 and are now their own small feature. `FEATURES.md` now has 5 features, in
order: feat-011 TLS floor + fail-closed → feat-012 performance budget CI → feat-013
distribution → feat-014 at-rest encryption → feat-015 optional pinning (opt-in, backup pin +
kill switch mandatory when enabled, reuses `RemoteConfig.disabledFeatures`). All 🟡 not
started.

Next session: start feat-011. Its entry already notes the likely finding — neither
`IngestClient` nor `RemoteConfigFetcher` has any unprotected-fallback code path today, so
SEC-12's deliverable there may be a locking-in test, not new code; confirm by reading both
files before assuming, and say so explicitly either way. The 5 unverified Phase 1
manual-checklist items stay open — don't close them synthetically. Android port starts only
after this epic closes.

## Parked

- **Android port** — explicitly sequenced *after* this epic by the user. Parity notes already
  written: `archive/epics/phase-1-2-wrap-up.md` → "What an Android port would need for
  parity." Nothing to do here yet.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `Sources/APMKit/Stability/SelfHealthCounters.swift` | Added | MOB-27 written/sent/dropped counters |
| `Sources/APMKit/Storage/DiskQueueEventSink.swift` | `try?` → real `do`/`catch`, counts written/dropped | MOB-27 hook |
| `Sources/APMKit/Storage/FileDiskQueue.swift` | Eviction now counts dropped | MOB-27 hook (MOB-06 eviction was previously uncounted) |
| `Sources/APMKit/Sync/SyncEngine.swift` | Counts sent/dropped on accepted/rejected; gained `isEnabled` closure (kill switch) | MOB-27 + MOB-21 |
| `Sources/APMKit/Stability/{RemoteConfig,RemoteConfigFetcher,RemoteConfigStore,KillSwitch}.swift` | Added | MOB-20/21 |
| `Sources/APMKit/IngestEndpoint.swift` | Added `configURL` | Sibling of `/v1/ingest`, shares MOB-10 anti-loop exclusion |
| `Sources/APMKit/Stability/ColdStartTracker.swift` | Added | MOB-19, host-invoked (no swizzling, MOB-12 precedent) |
| `Sources/APMKit/Stability/{HangObserving,HangDetector}.swift` | Added | MOB-18, wraps KSCrash `addHangObserver` |
| `Sources/APMKit/Crash/CrashReporter.swift` | `.watchdog` added to monitors | Fulfills feat-009's dated "feat-010 turns it on" decision |
| `Sources/APMKit/APMKit.swift` | +`startHangDetection`, `fetchRemoteConfig`, `recordFirstFrame` | New public entry points |
| `Tests/.../Stability/*.swift` | Added (5 files, 29 tests) | Coverage for all of the above |
| `Tests/APMKitTests/Crash/IOSCrashHarnessTests.swift` | +`phase3_hangDetection` | Real-Simulator proof, MOB-18 |
| `FEATURES.md` | feat-010 → ✅, checklist item 7 added; epic section rotated out entirely, Shipped entry added | Feature + epic closed, per `edts-harness` rotation.md's "when an epic completes" procedure |
| `archive/features/feat-010.md` | Added — full detail, decisions | Rotation |
| `archive/epics/apmkit-ios-sdk.md` | Added — moved epic section (PRD, scope, 10-feature table) | Epic rotation |
| `archive/epics/phase-1-2-wrap-up.md` | Added — full MOB-/SEC- coverage, deferred-to-Phase-3, real gaps, verification checklist state, Android parity | User-requested wrap-up |
| `FEATURES.md` | New epic filed: Pre-Pilot Hardening (feat-011..014, all 🟡) | User asked for the "real gaps" list turned into an actual follow-up epic, ordered by their stated priority, before Android starts |
| `FEATURES.md` | Re-scoped same epic: feat-011 split into TLS-floor-only (SEC-10/12), old pinning content moved to new feat-015 (SEC-11, now P2/opt-in) | User recorded a real SEC-11 decision in `docs/02-Mobile-SDK.md` §6.3 after reviewing the first proposal |

Verified live on this machine: Xcode 26.4, iOS 18.0 Simulator (iPhone 16 Pro). This turn was
scoping/planning only — no source files changed, `verify.sh` numbers are unchanged from the
feat-010 close.

_Ground truth: run `git diff --stat` to confirm this table matches reality._
