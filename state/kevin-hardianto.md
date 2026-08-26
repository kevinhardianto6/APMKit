# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Build the APM Kit iOS SDK (Phase 1 network observability + Phase 2 crash
  reporting), per docs/00-02.
- **Active feature:** feat-008 · Device Integrity
- **Status:** 🔵 in progress
- **Last verify:** `./verify.sh all` → `HARNESS_VERIFY: PASS (all)`, 2026-08-27 (baseline
  before starting feat-008; feat-001..007 all ✅ and archived, 117 tests passing).

## Next step

Flagged to user: their claimed docs/02 update (MOB-12 split, no-swizzling rationale, Android
parity note) isn't actually present in this repo's `docs/02-Mobile-SDK.md` — checked directly,
unchanged. Not blocking feat-008.

Building: `DeviceIntegrityDetector.snapshot()` → real `IntegritySnapshot` (feat-001's wire
shape, currently `.unset` everywhere). Design split for honest testability: pure
`JailbreakVerdict`/`DevModeVerdict` combination logic (portable, fully unit-tested truth
tables) vs. the real OS-level probes (`#if os(iOS)`-gated — file/symlink checks, sandbox
write attempt, provisioning-profile/receipt lookup — genuinely unverifiable via `swift test`
on macOS, only on a real device/simulator). `isEmulator()` via `#if targetEnvironment
(simulator)` — correct by construction but its `true` branch can't be exercised by `swift
test` either (always compiles for macOS host, never Simulator). `debugger_attached` via
`sysctl`+`P_TRACED`, made testable by injecting the raw process-flags read. "Once per
session" requirement: caching lands in `SessionManager` (already owns session
lifecycle/rotation), invalidated exactly when `appWillEnterForeground` rotates the session —
`EnvelopeFactory`'s `integrity` default now reads from there instead of `.unset`.

## Parked

- None.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `archive/features/feat-007.md` | Added | Rotated feat-007 detail on closing it |
| `archive/sessions/2026-08-27-feat-007.md` | Added | Rotated prior session's Changes table; noted the docs/02 discrepancy |
| `FEATURES.md` | feat-007 → ✅ (archived); feat-008 → 🔵 in progress; fixed a leftover duplicate block from an earlier edit | User approved feat-007 |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
