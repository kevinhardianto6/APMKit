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

feat-014 closed and committed (`3939eaa`) — full detail in `archive/features/feat-014.md`.

**feat-016 re-scoped, same day, before moving on:** the user asked for a recommendation on
whether feat-016 should include a sample app, given feat-012/013/014 all independently hit the
same "no app to test against" wall. Recommended yes — internal verification tooling only, not
MOB-25's own published/maintained sample app (Phase 3 stays separate) — user agreed and asked
it be written into `FEATURES.md` now. feat-016's entry and the epic-level notes both updated:
minimal blank-screen app, lives outside the SDK's `Package.swift`, spike the `.xcodeproj` cost
early and report back before building on it, checklist items 5/9 expected to close as a side
effect but not pre-marked. Nothing implemented — planning only.

Next up: **feat-015 (Optional Certificate Pinning, opt-in P2)**, per the fixed order.

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
| `FEATURES.md` | feat-016 entry expanded: internal verification app added to its scope, distinguished explicitly from MOB-25; epic-level note added | User-directed re-scope after reviewing the feat-012/013/014 pattern |

Prior changes this session (feat-014 itself) are committed — see commit `3939eaa` and
`archive/features/feat-014.md` for that detail, not repeated here.

_Ground truth: run `git diff --stat` to confirm this table matches reality._
