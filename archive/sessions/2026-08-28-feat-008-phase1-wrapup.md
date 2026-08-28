# Session — 2026-08-28 — feat-008 approval + Phase 1 wrap-up

Kevin Hardianto. User approved feat-008 outright, confirmed both open decisions (MOB-31
two-independent-booleans reading, SessionManager-owned caching) were correct, and confirmed
the docs/02 update (MOB-12 split + MOB-31 clarification) is now landed in the repo. Rotated
feat-008 to archive. Phase 1 (feat-001..008) is now complete — wrote a full
requirement-by-requirement wrap-up rather than just a feature list.

## Changes

| File | Change | Why |
|------|--------|-----|
| `archive/features/feat-008.md` | Added | Rotated feat-008 detail on closing it |
| `archive/epics/phase-1-wrap-up.md` | Added | Full MOB-/SEC- coverage accounting, deferrals, manual-verification list |
| `FEATURES.md` | feat-008 → ✅ (archived); pointer to the wrap-up added | Phase 1 complete |

## What went wrong / worth remembering

- Cross-checking the FULL MOB-/SEC- requirement list against what was actually built (rather
  than just listing which features shipped) surfaced several real gaps that were never
  flagged during any individual feature's review: the performance budget (docs/02 §5) isn't
  measured anywhere despite the spec saying a violation blocks release; SEC-08 (at-rest
  encryption), SEC-10 (explicit TLS enforcement), SEC-11/12/14 (pinning on the SDK's *own*
  ingest connection, as opposed to what feat-003 actually built — host-app pinning
  observability, a different thing), MOB-23/24 (CocoaPods, semver process) are all
  unimplemented and previously unflagged. Worth doing this kind of full-spec sweep at natural
  phase boundaries, not just trusting that per-feature reviews caught everything — a
  requirement with no assigned F-number is exactly the kind of thing that falls through.
- Distinguishing "deferred by design" (explicit epic scope boundary, like MOB-25/sample app)
  from "deferred because nobody assigned it" (like the performance budget) mattered for
  making the wrap-up actually useful rather than just a wall of unchecked boxes.

Evidence: `archive/features/feat-008.md`, `archive/epics/phase-1-wrap-up.md`.
