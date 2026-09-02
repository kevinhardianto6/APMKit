# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** No epic in progress. This session: a Backoffice-driven spec gap (docs/01
  §4.3.1/§4.3.2, MOB-17 extension) — `is_app` per frame/binary_image, plus a full audit +
  reshape of the `crash` payload to match the now-precise wire contract, and a confirmed
  no-change-needed audit of §4.5.1 breadcrumb snapshot shape.
- **Active feature:** none — implemented, tested, not yet committed.
- **Status:** —
- **Last verify:** `./verify.sh build`/`test`/`budget` → all PASS, 2026-09-02. 242 tests (was
  234 — added 8 for `is_app`/hex-address/arch/basename/thread-name reshaping).

## Next step

1. **Not yet committed:** everything below — user didn't say "commit" this time (unlike the
   prior three findings), so it's waiting on that per `CONSTITUTION.md`'s "never auto-commit."
2. **Report back to the user:** confirmed §4.5.1 breadcrumb shape already matches exactly, no
   change made there. Flagged that `FEATURES.md` item 6 (2026-08-28 Simulator crash
   verification) predates this reshape and doesn't cover the new shape — new item 11 added for
   that, still `☐ not verified`. Also worth a heads-up: this session started with a broken
   baseline build (stale `.build` module cache referencing the *old* repo path,
   `/Users/kevinhardianto/APMKit` → now `/Users/kevinhardianto/APM/APMKit`) — fixed by deleting
   the two affected `ModuleCache` dirs (main `.build` and `scripts/size-budget/.build`), not a
   code regression.
3. Manual verification checklist in `FEATURES.md` now has 11 items; unchanged priority
   otherwise from last session.

## Parked

- **Android port** — unblocked since Pre-Pilot Hardening closed, not yet scoped. Parity notes:
  `archive/epics/phase-1-2-wrap-up.md`.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

Previous session (README commit `ba17384`) closed out MOB-30/MOB-15b/MOB-11b — see that
session's own state-file history in git log if needed; not repeated here.

**This session — MOB-17 extension: `is_app`, full crash-payload reshape to docs/01 §4.3.1/§4.3.2.**

| File | What | Why |
|---|---|---|
| `Sources/APMKit/Crash/CrashReportMapper.swift` | New `reshapeBinaryImages`/`reshapeThreads`/`hexAddress`/`archString` helpers; `makeEvent` gains an `appBundlePath` param (default `Bundle.main.bundlePath`); `threads`/`binary_images` are now reshaped (not verbatim-passed) into the documented wire shape, including computed `is_app` | KSCrash's raw output never matched the now-precise §4.3.1/§4.3.2 contract at all (decimal addresses, full paths, `image_addr`/`image_size`/`cpu_type` instead of `base_addr`/`size`/`arch`, no `is_app`) — confirmed against real KSCrash source + `Example-Reports/*.json`, not assumed |
| `Tests/APMKitTests/Crash/CrashReportMapperTests.swift` | 8 new tests: `is_app` true/false for app vs. system binary and frame, app-owned embedded framework, empty-`appBundlePath` guard, hex-string addresses matching docs' own worked example, `cpu_type`→`arch` mapping (arm64/arm64e/x86_64), basename-not-full-path, `file`/`line` always null + `symbol_name` passthrough, thread `name` falls back to `dispatch_queue` | Proves the reshape against a realistic nested fixture built from confirmed real KSCrash shape |
| `CONSTITUTION.md` | New dated decision: the audit findings (not just `is_app` missing), how `is_app` is computed and why, the arch-mapping tradeoff, and the confirmed-matching breadcrumb audit | Full reasoning, matches this session's own "audit fully, report precisely" instruction |
| `FEATURES.md` | New manual checklist item 11 (real-device verification of the reshaped payload); caveat added to item 6 (predates this reshape, doesn't cover it) | Honest tracking — item 6's Simulator run wasn't broken by this change but isn't evidence for the new shape either |
| `docs/01-Kontrak-Data-API.md`, `docs/02-Mobile-SDK.md` | User's own edits (§4.3.1/§4.3.2 new sections, MOB-17 extended, plus unrelated §10 `drilldown` block and §11 formatting) — pulled and implemented against | Authoritative spec |

**Confirmed, no code change:** docs/01 §4.5.1's breadcrumb snapshot shape
(`timestamp`/`category`/`level`/`message`) already matches `Breadcrumb.swift`'s `Codable`
output field-for-field, including the ISO-8601-with-fractional-seconds `timestamp` format.

_Ground truth: run `git diff --stat` to confirm this table matches reality._
