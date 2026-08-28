# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Build the APM Kit iOS SDK (Phase 1 network observability + Phase 2 crash
  reporting), per docs/00-02.
- **Active feature:** none — feat-009 (Crash Reporting / KSCrash) closed ✅. Phase 2 not yet
  started on feat-010.
- **Status:** —
- **Last verify:** `./verify.sh build` and `./verify.sh test` → both `HARNESS_VERIFY: PASS`,
  2026-08-28. 149 tests. Plus a real-platform check outside that suite: `IOSCrashHarnessTests`
  passed on a booted iOS 18.0 Simulator via `xcodebuild test` (not part of `swift test`).

## Next step

feat-009 closed 2026-08-28 across 3 PRs — full detail rotated to `archive/features/feat-009.md`
(install/pipeline; macOS-host verification that caught a real `reason`-field mapping bug;
real iOS Simulator verification via a permanent `#if os(iOS)`-gated harness). feat-010
(Stability + Remote Control) is next in the mandatory build order — depends on feat-005,
feat-009, both done. Not started yet.

## Parked

- None.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `Sources/APMKit/Crash/CrashReporter.swift` | Added `installPath` override param to `install()` | Lets `IOSCrashHarnessTests` pin two separate Simulator process launches to the same on-disk KSCrash store |
| `Sources/APMKit/APMKit.swift` | `installCrashReporting` gained matching `installPath` param (default `nil`, no behavior change for real callers) | Same |
| `Tests/APMKitTests/Crash/IOSCrashHarnessTests.swift` | Added, `#if os(iOS)`-gated, kept permanently (user's call) | Real iOS Simulator crash verification — closes feat-009's actual "Done when" criterion; never runs on the macOS host so `verify.sh` is unaffected |
| `FEATURES.md` | feat-009 → ✅, table row + epic progress (9/10) updated, detail rotated to archive, checklist item 6 marked verified | Feature closed |
| `archive/features/feat-009.md` | Added — full PR 1/2/3 detail, decisions, review history | Rotation per `AGENTS.md` session-handoff rule |
| `archive/epics/phase-1-wrap-up.md` | Manual-verification list replaced with a pointer to `FEATURES.md` | User asked for one consolidated checklist, not scattered copies |

Verified live on this machine: Xcode 26.4, iOS 18.0 Simulator (iPhone 16 Pro). Exact
reproduction commands are in `IOSCrashHarnessTests.swift`'s header comment.

_Ground truth: run `git diff --stat` to confirm this table matches reality._
