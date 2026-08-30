# Session — 2026-08-29 — feat-010, feat-011, Pre-Pilot Hardening epic

One continuous session spanning: closing feat-010 (and the epic), filing and re-scoping the
Pre-Pilot Hardening follow-up epic, and closing its first feature (feat-011).

## Changes

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
| `Tests/.../Stability/*.swift` | Added (5 files, 29 tests) | feat-010 coverage |
| `Tests/APMKitTests/Crash/IOSCrashHarnessTests.swift` | +`phase3_hangDetection` | Real-Simulator proof, MOB-18 |
| `FEATURES.md` | feat-010 → ✅; epic section rotated out, Shipped entry added | Feature + epic closed, per rotation.md |
| `archive/features/feat-010.md` | Added — full detail, decisions | Rotation |
| `archive/epics/apmkit-ios-sdk.md` | Added — moved epic section | Epic rotation |
| `archive/epics/phase-1-2-wrap-up.md` | Added — full MOB-/SEC- coverage, deferred-to-Phase-3, real gaps, verification checklist state, Android parity | User-requested wrap-up |
| `FEATURES.md` | New epic filed: Pre-Pilot Hardening (feat-011..014, all 🟡) | User turned the "real gaps" list into a follow-up epic, ordered by their stated priority |
| `FEATURES.md`, `docs/00-Overview.md`, `docs/02-Mobile-SDK.md` | Re-scope: SEC-11 demoted P1→P2/opt-in (user's product decision, recorded in docs/02 §6.3); feat-011 split to TLS-floor-only, pinning moved to new feat-015 | Real product decision, not a technical one |
| `Sources/APMKit/Sync/SDKOwnedSessionConfiguration.swift` | Added | feat-011, SEC-10 TLS 1.2 floor for both SDK-owned sessions |
| `Sources/APMKit/Sync/IngestClient.swift`, `Sources/APMKit/Stability/RemoteConfigFetcher.swift` | Default session now built via `SDKOwnedSessionConfiguration.make()`; doc comments updated | feat-011 |
| `Tests/APMKitTests/Sync/IngestClientTests.swift`, `Tests/APMKitTests/Stability/RemoteConfigTests.swift` | +2 tests each: TLS-floor config assertion, real TLS-layer-failure fail-closed proof | feat-011 evidence |
| `FEATURES.md` | feat-011 → ✅, detail rotated to archive | Feature closed |
| `archive/features/feat-011.md` | Added — full detail; confirms SEC-12 was already true by construction, deliverable was a locking-in test not new code | Rotation |

## What went right / notable decisions

- **feat-010's kill switch proof** — one test flipping a shared `RemoteConfigStore` off/on,
  showing both capture and upload actually stop and resume, through real pipeline types.
  User confirmed this was exactly the rigor wanted.
- **feat-010's hang detection** — wrapped KSCrash's `Watchdog` monitor rather than hand-rolling
  a timer; verified live against a real 2.5s main-thread block on the iOS Simulator.
- **feat-011's SEC-12** — investigated before writing code; confirmed neither `IngestClient`
  nor `RemoteConfigFetcher` had any unprotected-fallback path, so the deliverable was a test
  locking that in, not new production code. User explicitly endorsed this as a legitimate
  outcome ahead of time, and the write-up says so plainly rather than inventing work.
- **feat-011's real-TLS-failure test technique** — pointing `https://` at a mock server that
  only speaks plain HTTP produces a genuine TLS-layer handshake failure (no ServerHello),
  avoiding the need to build actual self-signed-certificate test infrastructure while still
  meeting the "real, not mocked" bar this repo holds crash/hang verification to.
- **SEC-11 re-scope** — a real product decision (P1 mandatory pinning → P2 opt-in/off-by-
  default), recorded in the spec itself (`docs/02-Mobile-SDK.md` §6.3) before the epic was
  touched further. The agent proposed the feature breakdown and waited for explicit approval
  before writing it to `FEATURES.md`, per the user's explicit ask for that working pattern.

## Verification

178 tests at feat-010's close → 182 at feat-011's close. `./verify.sh build`/`test` both
`HARNESS_VERIFY: PASS` throughout, re-run multiple times including 3× explicit repeats on
feat-011's timing-sensitive real-TLS tests to rule out flakiness. Plus real iOS Simulator
checks outside the `swift test` count: `IOSCrashHarnessTests` phase 1/2/3 all passed via
`xcodebuild test` against a booted iOS 18.0 Simulator (iPhone 16 Pro, Xcode 26.4).

Commits this session: `6ea50a7` (feat-010 + epic filing/re-scope + docs decision, one combined
commit since the epic-scoping edits interleaved with feat-010's own `FEATURES.md` bookkeeping
in a way that wasn't cleanly splittable). feat-011 not yet committed as of this rotation —
see current `state/kevin-hardianto.md` for status.
