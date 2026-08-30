# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Pre-Pilot Hardening epic (2/5) — remediating P0/P1/P2 gaps the shipped APM
  Kit iOS SDK epic left unfiled, before the Android port starts.
- **Active feature:** none — feat-012 (Performance Budget, CI-enforced) closed ✅. feat-013
  (Distribution: CocoaPods + semver) is next per the epic's fixed order, not started.
- **Status:** —
- **Last verify:** `./verify.sh all` → `HARNESS_VERIFY: PASS (all)`, 2026-08-30. 185 tests,
  plus the new `budget` check (binary-size delta ~360KB, well under the 1.5MB threshold).

## Next step

feat-012 closed 2026-08-30 — full detail rotated to `archive/features/feat-012.md`. Built
`scripts/size-budget/` (throwaway two-executable SPM package, outside the SDK's own
`Package.swift` — measures the real linked-binary delta an "automatic" library product has no
artifact of its own to measure) + `scripts/check-binary-size-budget.sh`, a new `verify.sh
budget` mode, `Tests/APMKitTests/Sync/MainThreadIOStructuralTests.swift` (dynamic proof
`SyncEngine`'s automatic triggers don't block on slow disk/network), and a minimal
`.github/workflows/ci.yml` running `./verify.sh all` on every PR.

**Judgment call, as the user asked for explicitly:** cold-start overhead (≤30ms p95) was
*not* CI-gated — landed on treating it like CPU/memory (moved to the manual verification
checklist), reasoning: no sample host app exists to attach a meaningful cold-start measurement
to, and CI runner timing noise would swamp a 30ms budget regardless. Full reasoning in the
archive file. **Honest gap:** this repo has no git remote here, so the CI workflow itself has
never actually run on GitHub — only that its YAML is valid and it calls the same locally-
verified `./verify.sh all`. Flagged as manual-checklist item 8.

Not yet committed — see `git status` before starting feat-013. Session history before feat-012
(feat-010's close, the epic's filing/re-scope, feat-011) is in
`archive/sessions/2026-08-29-feat-010-011-and-hardening-epic.md`. The 5 unverified Phase 1
manual-checklist items stay open — don't close them synthetically. Android port starts only
after this epic closes.

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
| `scripts/size-budget/` (Package.swift, `Sources/Baseline`, `Sources/WithSDK`) | Added | feat-012 — throwaway SPM package to measure APMKit's real linked-binary size delta |
| `scripts/check-binary-size-budget.sh` | Added | feat-012 — builds both probes, gzip-diffs them, fails over 1.5MB |
| `verify.sh` | +`budget` mode, included in `all` | feat-012 |
| `AGENTS.md` | Verification section documents `budget`/`all`, notes what's NOT CI-checkable | feat-012 |
| `Tests/APMKitTests/Sync/MainThreadIOStructuralTests.swift` | Added (3 tests) | feat-012 — dynamic proof SyncEngine's automatic triggers don't block |
| `.github/workflows/ci.yml` | Added | feat-012 — minimal PR-triggered `verify.sh all` |
| `FEATURES.md` | feat-012 → ✅, detail rotated to archive, epic progress 2/5, checklist item 5 narrowed + item 8 added | Feature closed |
| `archive/features/feat-012.md` | Added — full detail, cold-start scope reasoning | Rotation |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
