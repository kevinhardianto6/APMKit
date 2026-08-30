# feat-012 · Performance Budget (CI-enforced)

- **Status:** ✅ done · closed 2026-08-30 · **Depends on:** feat-001..010 (measures the whole
  SDK as it exists today)
- **Requirements:** docs/02 §5 — binary size ≤1.5MB compressed, cold-start overhead ≤30ms p95,
  CPU ≤2% average, memory ≤8MB resident, disk ≤20MB, zero main-thread blocking I/O. "Diukur
  otomatis di CI, bukan diperiksa manual... Dilanggar = tidak boleh rilis."
- **Done when:** a runnable script/target measures binary-size delta and flags main-thread I/O,
  gated in CI. **Met, for the part that's honestly CI-measurable** — see Scope below for what
  isn't, and why.

## Scope decision — what's CI-enforceable vs. what needs a real device

Per the user's explicit direction before this feature started: split the budget by what CI can
honestly measure, rather than inventing synthetic numbers to make everything look enforced.

**CI-enforced (this feature):**
- **Binary size delta** — real, gated, fails the build over threshold.
- **Main-thread I/O** — structural, dynamic proof for the SDK's own automatic entry points.

**Explicitly NOT CI-enforced, moved to the pilot's manual verification checklist
(`FEATURES.md`), not invented:**
- **CPU ≤2% average, memory ≤8MB resident** — per the user's own instruction: these need
  profiling on a device under a realistic workload, which a CI runner cannot honestly provide.
- **Cold-start overhead ≤30ms p95** — the judgment call the user asked this feature to make
  explicitly. Landed on: **treat it like CPU/memory, hand it to the pilot.** Reasoning:
  1. There's no sample/host app in this repo to attach a "time-to-first-frame with vs. without
     the SDK" measurement to (MOB-25 is Phase 3, out of scope) — the only thing buildable here
     is a bare command-line executable (see the size-budget probes below), which has no
     UIKit/SwiftUI view hierarchy or `CATransaction` commit to measure "first frame" against
     at all. A number from that would describe "how long `main()` took," not cold-start
     overhead in any sense docs/02 §5 means.
  2. GitHub-hosted CI runners are shared, virtualized hardware with real scheduling jitter —
     a 30ms p95 budget is tight enough that VM noise alone could dominate the signal, producing
     numbers that look precise but aren't meaningful.
  3. Both problems are the *same class* of problem the user already identified for CPU/memory
     (needs a controlled, realistic device environment) — not a different one that happens to
     be borderline measurable. Inventing a proxy number just to claim something's gated would
     be exactly the "synthetic number to make it look enforced" the user asked not to do.

## What was built

- **`scripts/size-budget/`** — a separate, throwaway two-executable SPM package (`Baseline`,
  no APMKit import; `WithSDK`, imports and touches a broad slice of the public API including
  the crash-reporting path, so the linker can't dead-strip APMKit — and KSCrash — away and
  under-report the delta). Kept **outside** the SDK's own `Package.swift`, which AGENTS.md is
  explicit has "no app target" — this doesn't add one, it's CI tooling that happens to be an
  SPM package. An "automatic" library product (which `APMKit` is) has no linked artifact of
  its own to measure directly; only a real consumer does, which is exactly what `WithSDK`
  stands in for. Same "throwaway harness package" technique feat-009 used for its macOS crash
  harness, just checked into the repo (under `scripts/`) instead of scratchpad, since CI needs
  to run it reproducibly rather than once, interactively.
- **`scripts/check-binary-size-budget.sh`** — builds both probes in release mode, gzip-
  compresses both binaries ("terkompresi" per the spec), diffs the sizes, fails if the delta
  exceeds 1.5 MiB (`1,572,864` bytes — the spec doesn't say binary vs. decimal MB; this is a
  documented, defensible choice, not a silent assumption). Currently measures **~360 KB**
  compressed delta, well under budget.
- **`verify.sh`** gained a `budget` mode (and `all` now includes it) — no new ad-hoc script
  outside the existing verification entry point.
- **`Tests/APMKitTests/Sync/MainThreadIOStructuralTests.swift`** — dynamic, not just
  by-inspection: wraps `DiskQueue`/`IngestUploading` with artificial 0.5s latency and asserts
  `SyncEngine.appDidEnterBackground()`/`.connectivityRestored()` still return in well under
  50ms, proving the actual I/O happens on `SyncEngine`'s own `workQueue`, not synchronously on
  the caller — a real regression guard: if either method were changed to `workQueue.sync`
  instead of `.async`, this test would fail. Also asserts `APM.instrumentedSession()`'s
  `URLSession.delegateQueue` is never `OperationQueue.main` (identity comparison against the
  singleton — `.underlyingQueue` isn't reliably set either way, so that wouldn't have been a
  meaningful check).
  - **Explicitly not covered, by design:** the manual APIs (`APM.logError`, `APM.breadcrumb`,
    `APM.recordFirstFrame`) are synchronous by construction (`ManualReporter`'s own doc comment
    already says "whatever thread the host calls them on") — if a host app calls one from its
    own main thread, that call does block on disk I/O. This is pre-existing, documented
    behavior this feature doesn't change; flagged here rather than silently left unmentioned.
- **`.github/workflows/ci.yml`** — one job, `macos-latest`, running `./verify.sh all` on every
  PR and on push to `main`. Deliberately minimal per the user's instruction — no release/
  signing/distribution steps, just the same command a contributor runs locally.

## Verification

185 tests (was 182 at feat-011's close; +3, all in `MainThreadIOStructuralTests`).
`./verify.sh all` → `HARNESS_VERIFY: PASS (all)`, re-run multiple times, all four sub-checks
(build/test/lint/budget) green.

**Honest limitation:** this repo has no git remote configured in this environment, so the
GitHub Actions workflow itself has not been observed actually running on GitHub's
infrastructure — only that its YAML is syntactically valid (`ruby -ryaml`) and that it invokes
exactly the same `./verify.sh all` already verified to pass locally. Confirm the workflow
actually fires and gates a real PR once this repo has a remote.

**Decisions** — the cold-start scope call above; everything else per the epic's own already-
recorded scope. **Blockers** — none.

**Files added:** `scripts/size-budget/` (Package.swift + `Sources/Baseline`, `Sources/WithSDK`),
`scripts/check-binary-size-budget.sh`, `.github/workflows/ci.yml`,
`Tests/APMKitTests/Sync/MainThreadIOStructuralTests.swift`.
**Files amended:** `verify.sh` (+`budget` mode), `AGENTS.md` (Verification section).
