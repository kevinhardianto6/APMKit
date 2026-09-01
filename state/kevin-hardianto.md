# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Bug fix (real-run pilot finding, not a `FEATURES.md` epic item): clean
  Simulator sessions report `integrity.is_rooted = true` (false positive). Root cause: the
  sandbox-write probe in `DeviceIntegrityDetector.isRooted()` (MOB-30) structurally always
  succeeds on Simulator (unsandboxed macOS process), and that `true` was feeding straight into
  `JailbreakVerdict.isRooted`'s OR-combination.
- **Active feature:** MOB-30 Simulator false-positive fix (ad hoc, reported by user this
  session from the pilot ingestion server's real traffic).
- **Status:** ✅ fixed and verified this session. `is_rooted` end-to-end on a real Simulator is
  still on the manual checklist (`FEATURES.md` item 1) — the fix's *logic* is unit-tested, its
  live Simulator behavior is not (same host-toolchain limit as everything else in item 1).
- **Last verify:** `./verify.sh build`/`test`/`budget` → all PASS, 2026-09-01. 228 tests (was
  225 — added 3 for `JailbreakVerdict.sandboxWriteSignal`).

## Next step

Epic closed — full detail `archive/epics/pre-pilot-hardening.md`, this session's own account
`archive/sessions/2026-08-31-feat-015-016-epic-shipped.md`. **Nothing is currently scoped as a
ready (🟡) feature in `FEATURES.md`.**

The next real decision (per `AGENTS.md`'s own sequencing, `CONSTITUTION.md`, and this epic's
own note): **Android port** is now unblocked but not yet scoped into `FEATURES.md` — parity
notes are ready at `archive/epics/phase-1-2-wrap-up.md` → "What an Android port would need for
parity," but scoping it into epics/features is a decision to make *with* the user next session,
not something to assume and start solo.

Also still open, not part of any active epic: manual verification checklist items 1–4 and 8 in
`FEATURES.md` (Phase 1 device/Simulator checks that were never revisited), and item 5's
real-device cold-start profiling (feat-016 got Simulator numbers, not the real thing).

**feat-016's changes are staged but not committed** — commit is a separate step per
`CONSTITUTION.md`'s "never auto-commit."

## Parked

- **Android port** — unblocked as of this epic's close, not yet scoped. See above.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

Previous session's table: `archive/sessions/2026-08-31-feat-015-016-epic-shipped.md` (feat-015,
feat-016, epic rotation).

This session — MOB-30 Simulator `is_rooted` false-positive fix:

| File | What | Why |
|---|---|---|
| `Sources/APMKit/Integrity/IntegrityVerdicts.swift` | Added `JailbreakVerdict.sandboxWriteSignal(isSimulator:rawWriteSucceeded:)` | Pure, host-testable mapping that discards the sandbox-write probe's raw result on Simulator (structurally always succeeds there) and passes it through unchanged on device |
| `Sources/APMKit/Integrity/DeviceIntegrityDetector.swift` | `isRooted()` now routes `canWriteOutsideSandbox()`'s result through `sandboxWriteSignal`; expanded the file-header doc comment with the 2026-09-01 finding and its honesty caveats | Fixes the false positive without touching real-device combination logic; documents what is/isn't proven, same as feat-008's existing honesty note |
| `Tests/APMKitTests/Integrity/IntegrityVerdictsTests.swift` | Added 3 tests: Simulator discards raw `true`/`false`, device passes through unchanged, end-to-end clean-Simulator combination is `false` | Proves the fix's logic on the macOS host (the live Simulator probe itself still needs a real run — see below) |
| `FEATURES.md` | Updated manual-checklist item 1 with a 2026-09-01 note | Keeps the one running pre-ship checklist current rather than scattering a new row |
| `CONSTITUTION.md` | Added a dated decision entry | Records the two options considered (skip probe vs. weaken combination logic) and why (b) was chosen, plus why file/symlink probes were left alone |

_Ground truth: run `git diff --stat` to confirm this table matches reality._

## Next step (superseding "Epic closed" above for the immediate next session)

MOB-30 fix is done and verified (build/test/budget all PASS, 228 tests) but **not committed**
— per `CONSTITUTION.md`'s "never auto-commit," commit is the user's call. Suggested message:
`fix: MOB-30 Simulator is_rooted false positive (sandbox-write probe)`. After that, the actual
next decision is still the Android-port scoping conversation noted below — this was an
interrupt, not a new epic.
