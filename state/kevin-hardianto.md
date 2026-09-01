# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** No epic in progress (Pre-Pilot Hardening shipped 2026-08-31). This session
  closed out two ad hoc real-run pilot findings end-to-end, including a spec decision from the
  user and its implementation. Not `FEATURES.md` epic work.
- **Active feature:** none — both findings are done, verified, and committed.
- **Status:** —
- **Last verify:** `./verify.sh build`/`test`/`budget` → all PASS, 2026-09-01. 231 tests.

## Next step

1. **Real decision still pending, unrelated to this session:** Android-port scoping — see
   Parked below. A conversation with the user, not something to start solo.
2. Manual verification checklist in `FEATURES.md` now has 10 items — items 1–4, 8, and the new
   item 10 (`termination` event, real OOM/thermal/CPU/battery kill) are `☐ not verified`; item
   5 needs real-device (not Simulator) profiling. Unchanged priority, just more items.
3. Nothing else in flight.

## Parked

- **Android port** — unblocked since Pre-Pilot Hardening closed, not yet scoped. Parity notes:
  `archive/epics/phase-1-2-wrap-up.md`. Note for whenever it's picked up: the `termination`
  event type (added this session) was deliberately designed with Android's
  `ApplicationExitInfo` parity in mind — see `CONSTITUTION.md`'s 2026-09-01 decision.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

Previous session: `archive/sessions/2026-08-31-feat-015-016-epic-shipped.md` (feat-015,
feat-016, epic rotation).

**Finding 1 — MOB-30 Simulator `is_rooted` false positive.** Committed `dee3b17`.
`JailbreakVerdict.sandboxWriteSignal(isSimulator:rawWriteSucceeded:)` discards the
sandbox-write probe's raw result on Simulator (structurally always succeeds there, unsandboxed
process) and passes it through unchanged on device. 3 new tests in `IntegrityVerdictsTests`.

**Finding 2 — SIGKILL/termination reports mis-mapped as `crash`, now a dedicated event type.**
User approved the root cause, then made and pushed a spec decision (docs/01 §4.6/§4.7, docs/02
MOB-15b: new `termination` event type, `termination_reason` enum of 5 resource-kill causes,
`unexplained` dropped entirely). Implemented against the updated spec — committed alongside
this session's other changes.

| File | What | Why |
|---|---|---|
| `Sources/APMKit/Crash/CrashReportMapper.swift` | `errorType == "termination"` now routes to new `makeTerminationEvent`, which emits `type: "termination"` (attrs `termination_reason`, `time_since_launch_ms`) when `error["termination_reason"]` is one of `memory_limit`/`memory_pressure`/`cpu`/`thermal`/`low_battery`, else returns `nil` (drops `unexplained` and anything else). Extracted shared `timeSinceLaunchMs`/`appState` helpers used by both `crash` and `termination` paths. | Implements docs/01 §4.7 / docs/02 MOB-15b exactly as specified |
| `Tests/APMKitTests/Crash/CrashReportMapperTests.swift` | Replaced the old "always nil" termination test with 3: the 5 resource reasons → `termination` event with correct attrs; `unexplained` + 8 other real `KSTerminationReason` strings → `nil`; missing `termination_reason` → `nil` | Proves both branches of the new spec, parametrized over every value KSCrash can actually produce |
| `CONSTITUTION.md` | New dated decision recording the landed spec decision and its reasoning (parity, retrospective-discovery, actionability) | Keeps the "why" alongside the "what," per this file's own rule |
| `FEATURES.md` | Removed the now-resolved "Pending spec decisions" table; added manual-checklist item 10 (real OOM/thermal/CPU/battery kill → `termination` event, unverifiable by `swift test`) | Tracks the one thing about this feature that still needs a real device/Simulator run |
| `docs/01-Kontrak-Data-API.md`, `docs/02-Mobile-SDK.md` | User's own edits (§4.6 clarification, new §4.7, MOB-15b) — not authored this session, pulled and implemented against | Authoritative spec, per `AGENTS.md`/`CONSTITUTION.md` |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
