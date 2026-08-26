# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Build the APM Kit iOS SDK (Phase 1 network observability + Phase 2 crash
  reporting), per docs/00-02.
- **Active feature:** feat-006 · Identifier & Manual API
- **Status:** 🔵 in progress
- **Last verify:** `./verify.sh all` → `HARNESS_VERIFY: PASS (all)`, 2026-08-24 (baseline
  before starting feat-006; feat-001..005 all ✅ and archived, 97 tests passing).

## Next step

Implementing: `UserIdentity` (enum, mirrors `InstallIdentity`'s style) — `setUser(id:)` stores
the raw string verbatim (never hashed/validated, per user's explicit reminder — hashing to
`user_ref` is the backend's job); `currentUserId()` returns the explicit value or a stable
random fallback generated once and persisted per install, in its own UserDefaults key
(distinct from `install_id` — separate concepts even though both are "stable per install").
`EnvelopeFactory`'s default `userId` closure switches from `{ nil }` to
`{ UserIdentity.currentUserId() }`. `ManualReporter` (new, parallels `NetworkCaptureDelegate`'s
explicit-dependency style) for `logError(_:context:)` → `error` event (docs/01 §4.4).
User specifically wants a leak-proof test — critically, `user_id` never touches the disk
queue at all in this architecture (Envelope, which carries it, is only assembled in-memory at
upload time from a batch of `Event`s; individual `Event`s never carry it), so the test proves
the stronger property: a raw PII-shaped user_id never appears anywhere in queued Event JSON
or actual queue-file bytes, across unrelated network/error events in the same session.

## Parked

- None.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `archive/features/feat-005.md` | Added | Rotated feat-005 detail on closing it |
| `archive/sessions/2026-08-24-feat-005.md` | Added | Rotated prior session's Changes table |
| `FEATURES.md` | feat-005 → ✅ (archived); feat-006 → 🔵 in progress | User approved feat-005 + anti-loop fix |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
