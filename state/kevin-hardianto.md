# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Build the APM Kit iOS SDK (Phase 1 network observability + Phase 2 crash
  reporting), per docs/00-02.
- **Active feature:** feat-007 · Breadcrumbs
- **Status:** 🔵 in progress
- **Last verify:** `./verify.sh all` → `HARNESS_VERIFY: PASS (all)`, 2026-08-24 (baseline
  before starting feat-007; feat-001..006 all ✅ and archived, 107 tests passing).

## Next step

User decision on MOB-12 (asked via AskUserQuestion): NO UIViewController swizzling for
screen-transition breadcrumbs — crash/conflict risk (e.g. vs Firebase's own swizzling) isn't
worth it. Manual `APM.recordScreen(_:)` primitive + opt-in helpers instead
(`APMTrackedViewController` base class, `View.apmScreen(_:)` SwiftUI modifier), defaulting to
type name. **Flagged for user to update docs/02:** MOB-12 should say host-invoked screen
tracking with SDK-provided helpers, not "automatic."

Architecture: breadcrumbs live in an in-memory `BreadcrumbRingBuffer` (cap 100), NOT queued as
individual disk events (docs/00 glossary frames them as "black box recorder" — only useful
attached to an error) — `ManualReporter.logError` JSON-serializes a snapshot into the `error`
event's `breadcrumbs` attr, which then flows through the EXISTING `Scrubber` blanket
`PatternRedactor` pass with zero new scrubbing code. Lifecycle (`#if os(iOS)`,
`UIApplication` notifications) + connectivity (`NWPathMonitor`, cross-platform) are auto-wired
via `AutomaticBreadcrumbSource.start()`, with internal `recordLifecycle`/`recordConnectivity`
methods exposed for testing the mapping logic without needing real OS-level triggers. Building
now; required test per user: a phone number in a breadcrumb message must never reach disk,
proven through the real Scrubber→FileDiskQueue pipeline like `UserIdentityLeakTests`.

## Parked

- None.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `archive/features/feat-006.md` | Added | Rotated feat-006 detail on closing it |
| `archive/sessions/2026-08-24-feat-006.md` | Added | Rotated prior session's Changes table; noted the test-count typo correction |
| `FEATURES.md` | feat-006 → ✅ (archived); feat-007 → 🔵 in progress | User approved feat-006 |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
