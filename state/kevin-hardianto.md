# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Build the APM Kit iOS SDK (Phase 1 network observability + Phase 2 crash
  reporting), per docs/00-02. Repo just converted from Xcode framework scaffold to a real SPM
  package (Package.swift, Sources/APMKit, Tests/APMKitTests).
- **Active feature:** none yet — proposal (package structure, public API, F1-F10 mapping)
  presented and awaiting go-ahead before starting feat-001.
- **Status:** —
- **Last verify:** `./verify.sh all` → PASS (build + test) on the empty scaffold, 2026-08-24.

## Next step

Get sign-off on the proposal, then start feat-001 (Core & Envelope) in FEATURES.md.

## Parked

- None.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `docs/*.md` | Added (copied from spec source) | Versioned source of truth for MOB-/SEC- reqs |
| `Package.swift`, `Sources/`, `Tests/` | Added; removed `APMKit.xcodeproj`/`APMKitTests` | Spec deliverable is SPM, not an Xcode framework project |
| `verify.sh` | Rewritten for `swift build`/`swift test` | Matches new SPM structure |
| `AGENTS.md`, `CONSTITUTION.md`, `FEATURES.md` | Updated | Reflect SPM/iOS15, pipeline invariants, F1-F10 backlog |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
