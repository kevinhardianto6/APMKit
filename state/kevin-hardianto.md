# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** No epic in progress (Pre-Pilot Hardening shipped 2026-08-31). This session is
  three ad hoc real-run pilot findings, each: investigated, fixed/spec'd with the user, tested,
  committed. Not `FEATURES.md` epic work.
- **Active feature:** none — all three findings are done, verified, and committed.
- **Status:** —
- **Last verify:** `./verify.sh build`/`test` → all PASS, 2026-09-01. 234 tests.

## Next step

1. **Real decision still pending, unrelated to this session:** Android-port scoping — see
   Parked below.
2. Manual verification checklist in `FEATURES.md` has 10 items, mostly unchanged by this
   session — items 1–4, 8, 10 are `☐ not verified`; item 5 needs real-device profiling.
3. **Not yet committed:** `README.md` (documents findings 2 and 3 for SDK consumers) — the
   user's own call per `CONSTITUTION.md`'s "never auto-commit."

## Parked

- **Android port** — unblocked since Pre-Pilot Hardening closed, not yet scoped. Parity notes:
  `archive/epics/phase-1-2-wrap-up.md`. The `termination` event type and the `logError`
  call-site fields were both designed with Android parity in mind (`ApplicationExitInfo`,
  stack-frame file/function/line) — see `CONSTITUTION.md`'s 2026-09-01 decisions.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

Previous session: `archive/sessions/2026-08-31-feat-015-016-epic-shipped.md`.

**Finding 1 — MOB-30 Simulator `is_rooted` false positive.** Committed `dee3b17`.
`JailbreakVerdict.sandboxWriteSignal` discards the sandbox-write probe's structurally-always-
true result on Simulator; device logic untouched. 3 new tests.

**Finding 2 — SIGKILL mis-mapped as `crash`.** Committed `074a8f5`. New `termination` event
type (docs/01 §4.7, docs/02 MOB-15b, user's spec decision): `CrashReportMapper` emits it only
for the 5 resource-kill `termination_reason` values, drops `unexplained` entirely. 3 new tests.

**Finding 3 — `logError` gains call-site capture (docs/01 §4.4, §6, docs/02 MOB-11b).**
Committed `5f44695`. Pilot data showed one error message repeated 8x with no way to tell which
call site — the old fingerprint (domain+code+message) would've merged genuinely different bugs.

| File | What | Why |
|---|---|---|
| `Sources/APMKit/Identity/ManualReporter.swift` | `logError` gains `file: String = #fileID, function: String = #function, line: Int = #line` params; emits `source_file`/`source_function`/`source_line` attrs | Auto-captures the call site, zero dev effort/runtime cost. **Must stay `#fileID`, never `#file`** — `#file` is the absolute build path, leaks the dev's username; SEC-05's scrub patterns (phone/email/JWT) wouldn't catch it |
| `Sources/APMKit/APMKit.swift` (`APM.logError`), `Sources/APMKit/Composition/APMInstance.swift` (`APMInstance.logError`) | Both gain the same 3 default params, declared on *their own* signature and forwarded explicitly | Default-param expressions evaluate at their own call site — a wrapper relying on the inner method's default instead of declaring+forwarding its own would capture the SDK's file, not the app's |
| `Tests/APMKitTests/Identity/ManualReporterTests.swift` | 3 new tests: `source_file` has no leading `/` and no `/Users/` (the `#file`-regression guard), `source_function`/`source_line` match the real call site, explicit params override the default | Proves the #fileID contract directly — this is the part that would silently regress if someone "fixed" it to `#file` |
| `CONSTITUTION.md` | New dated decision: why `#fileID` not `#file`, why `source_line` is excluded from the (backend-owned) fingerprint, why defaults must be re-declared at every layer | Full reasoning alongside the rule |
| `docs/01-Kontrak-Data-API.md`, `docs/02-Mobile-SDK.md` | User's own edits (§4.4 new attrs, §6 fingerprint change, MOB-11b) — pulled and implemented against | Authoritative spec |

**README update — not yet committed.** Documented findings 2 and 3 for SDK consumers: new
"Termination reporting" feature bullet, `logError` bullet + quick-start comment note the
auto-captured call site, and a new privacy-notes bullet on `#fileID` vs `#file`.

_Ground truth: run `git diff --stat` to confirm this table matches reality._
