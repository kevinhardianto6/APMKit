# feat-009 · Crash Reporting (KSCrash)

- **Status:** ✅ done · closed 2026-08-28 · **Depends on:** feat-001, feat-002, feat-003,
  feat-004, feat-005, feat-006, feat-007, feat-008 (end of Phase 1)
- **Requirements:** wrap KSCrash (do not hand-roll signal/mach handlers). On crash, write a
  minimal report to disk (no PII), send on next launch; include `binary_images` + UUIDs for
  later symbolication. MOB-15/16/17. Highest-risk feature (crash handler is the sole component
  intentionally running during a crash, per `CONSTITUTION.md`) — spanned 3 PRs, sub-split per
  the spec's own guidance rather than rushed.
- **Done when:** a forced crash is captured and appears in the mock backend after relaunch;
  raw on-disk report is minimal (no PII) — see docs/02 §6.2 trade-off box on why the raw crash
  report is unencrypted at write time. **Met** — verified end-to-end on both a macOS-host
  harness and a real iOS Simulator run (PR 2 / PR 3 below). "Mock backend" here means the
  SDK's own `FileDiskQueue`, reached through the real `Scrub → Disk` pipeline — there is no
  separate mock-backend component in this repo; `SyncEngine`/`IngestClient` (feat-005) already
  own actually shipping a queued event to a server and were not re-verified by this feature.

## PR 1 — installation, capture wiring, next-launch pipeline

Evidence: `./verify.sh build` / `./verify.sh test` → both `HARNESS_VERIFY: PASS`, 148 tests
(131 at feat-008 close + 17 new).

- Added `KSCrash` (kstenerud/KSCrash 2.6.0) as the sole Phase-2 dependency — the only feature
  permitted to add one (`CONSTITUTION.md`). Depends on library product `Recording`, module
  `import KSCrashRecording`.
- `Sources/APMKit/Crash/`: `CrashReporter` (installs KSCrash monitors + wires breadcrumb
  mirroring), `CrashUserInfoStore`/`CrashReportSource` (narrow protocols over KSCrash's
  concrete types, for testability without touching real signal handlers), `CrashReportMapper`
  (pure `[String: Any]` → `Event` per docs/01 §4.3), `CrashReportProcessor` (orchestrates
  next-launch read → map → `sink` → delete), `CrashBreadcrumbEncoder`.
- `APM.installCrashReporting()` / `APM.processPendingCrashReports(sink:sessionManager:)` —
  new public entry points, same explicit-dependency style as `logError`/`instrumentedSession`.
- `BreadcrumbRingBuffer` gained an `onAdd` hook so breadcrumb mirroring can piggyback on the
  existing single call site (`APM.breadcrumb`) without new ambient state.

**Decisions**
- **Monitors enabled:** `machException, signal, cppException, nsException, userReported,
  termination` — i.e. `KSCrashMonitorTypeProductionSafeMinimal` minus `Watchdog` (hang
  detection). Watchdog/hang is MOB-18, explicitly feat-010's requirement in this table —
  enabling it here would be scope creep across the mandatory build order (`CONSTITUTION.md`:
  one feature at a time, out-of-scope ideas become new rows not drive-by edits). `crash_type:
  hang` is still decoded defensively by `CrashReportMapper` so feat-010 only has to flip the
  monitor flag, not touch this mapping. Recorded as a dated `CONSTITUTION.md` decision
  (2026-08-28).
- **SEC-09 compliance mechanism:** the raw KSCrash report is written by KSCrash's own
  async-signal-safe internals — this SDK never scrubs at crash time (can't: allocation is
  unsafe in a signal handler). Instead: (a) `enableMemoryIntrospection` stays `false`
  (framework default, set explicitly) since it can pull arbitrary object/string contents into
  the raw report — the single biggest unbounded-PII risk KSCrash offers; (b) breadcrumbs are
  scrubbed *before* being mirrored into KSCrash's per-key user info, at normal breadcrumb-add
  time (not crash time) — see `CrashBreadcrumbEncoder`; (c) exception `name`/`reason` (which
  *can* carry PII — e.g. an `NSException` reason built from user data) are only scrubbed at
  next-launch processing time, when `CrashReportProcessor` routes the mapped event through the
  same `sink` (Scrubber) every other event goes through. This means the raw file sitting in
  KSCrash's own store between crash and next launch is **not** fully PII-free in the
  exception-reason case — accepted as the documented trade-off (docs/02 §6.2 box), same
  window the spec already calls out for encryption. **Confirmed working under a real crash**
  in PR 2/3: breadcrumb PII and exception-reason PII both came back `[redacted]` after the
  next-launch scrub pass.
- **Report schema mapping** initially verified against KSCrash's own `Example-Reports/*.json`
  fixtures (checked out via SPM, not committed to this repo) — later found to not fully match
  the real installed version's shape (see PR 2).

**Review fixes (post-PR-1, pre-PR-2)**
- MOB-17 confirmed already satisfied — `CrashReportMapper` copies `report["binary_images"]`
  (each entry carries `uuid`) straight through as JSON; `CrashReportMapperTests
  .threadsAndBinaryImagesAreJSONEncoded` asserts the UUID survives.
- **Fixed a real gap:** `processPendingCrashReports` was a second call the host had to
  remember, separately from `installCrashReporting` — same failure shape as feat-005's
  anti-loop problem (a safety property depending on integrator memory isn't a guarantee).
  Folded into one call: `APM.installCrashReporting(sink:sessionManager:)` now installs KSCrash
  *and* drains the previous run's pending reports, dispatched to a private background queue so
  a launch-time call from the main thread never becomes blocking I/O (docs/02 §5). The
  standalone `processPendingCrashReports` stays public for tests/explicit control, but normal
  integrations never need to call it directly.

## PR 2 — real end-to-end verification (macOS host)

This repo has no app target (AGENTS.md), so a full iOS host app was out of scope for a first
pass; KSCrash also ships a macOS platform target, and this repo already treats macOS as its
host-toolchain target for `verify.sh`. Built a throwaway two-process harness in the scratchpad
(never committed — a local SPM executable depending on this repo by path):
1. Process A: `APM.installCrashReporting(sink:sessionManager:)`, two breadcrumbs (one with a
   fake phone number), then `NSException(name: "HarnessTestCrash", reason: "...081234567890...
   ").raise()`. Verified it actually terminates the process (exit 134) and KSCrash writes a
   report to its own store (`~/Library/Caches/KSCrash`).
2. Process B (fresh launch): `APM.installCrashReporting` again, poll the real `FileDiskQueue`
   until the background-drained event lands, print it.

**Result — confirmed working:** `crash_type: exception`, `name: HarnessTestCrash`,
`is_fatal: true`, `binary_images`/`threads` present with a real UUID, breadcrumbs stitched in
via the real `CrashReportStore` API with the phone number rendered as `[redacted]` (proves the
scrub-before-mirror SEC-09 design holds under a real crash, not just a fixture), and
`time_since_launch_ms` populated.

**Result — caught a real bug, now fixed:** `reason` came back empty on the first run. Real
KSCrash 2.6.0 puts `NSException` reason at `crash.error.reason` (top level), not nested under
`crash.error.nsexception.reason` like the `Example-Reports/*.json` fixtures (an older report
version) assumed. `CrashReportMapper.extractNameReason` now reads the top-level `reason` as a
fallback for every branch, and `isFatal` now prefers the real report's own top-level
`is_fatal` field when present over the hang-only heuristic. Added
`CrashReportMapperTests.realKSCrash260NSExceptionShapeReasonIsTopLevel` (regression, built
from the real captured shape) — 149 tests total. This is exactly the class of bug fixture-only
unit tests can't catch — a crash report that arrives complete but with an empty reason is
silent data loss that survives green tests for months.

## PR 3 — real iOS Simulator verification (closes the feature)

The macOS harness (PR 2) proves the logic, not the shipping platform — explicitly not treated
as sufficient to call this feature done. Chosen approach (user decision, see below): add a
permanent `#if os(iOS)`-gated two-phase Swift Testing suite,
`Tests/APMKitTests/Crash/IOSCrashHarnessTests.swift`, run via two separate `xcodebuild test
-only-testing:` invocations against a booted Simulator — never part of `swift test`/
`./verify.sh test` on the macOS host, so it costs nothing day-to-day.

- Added an `installPath` override to `CrashReporter.install(installPath:)` /
  `APM.installCrashReporting(sink:sessionManager:installPath:)` (defaults to `nil`, i.e. no
  behavior change for real callers) so the harness can point two *separate* Simulator process
  launches (each a fresh app-container UUID under `xcodebuild test`) at the same fixed on-disk
  KSCrash store.
- `IOSCrashHarnessTests`: `phase1_forceCrash()` installs, records a breadcrumb with a fake
  phone number, raises a real `NSException`. `phase2_readBackAfterRelaunch()` (a *separate*
  process/invocation) installs again, polls the real `FileDiskQueue`, and asserts on the
  drained `crash` event.
- `@Suite(.serialized)` added as a second line of defense — Swift Testing runs a suite's tests
  in parallel by default, which was observed running phase 2 concurrently with phase 1 when no
  leaf-level `-only-testing:` filter was given. The doc comment is explicit that the leaf
  filter (with a required trailing `()`) is still what actually enforces ordering; the trait
  just protects against forgetting it.
- **Verified working**, Xcode 26.4 / iOS 18.0 Simulator, twice (once during setup, once as a
  clean rerun of the exact commands now documented in the file's header comment) — phase 1
  crashes as expected, phase 2 passes, asserting `crash_type: exception`,
  `name: IOSCrashHarnessTestCrash`, `reason` redacted (not empty, not raw PII), `binary_images`
  non-empty, breadcrumbs present with the phone number as `[redacted]`.

**Decisions**
- **Setup choice (xcodebuild/XCTest harness vs. a hand-built .app + simctl) — user's call**,
  asked via two explicit questions rather than picked unilaterally: (1) which approach to
  build, (2) whether the resulting harness should stay in the repo or be thrown away. User
  chose the `xcodebuild test` approach (lowest effort, good fidelity, no app target needed —
  SPM auto-generates the test scheme) and chose to **keep it committed**, reasoning that the
  macOS harness is what caught the empty-reason bug in PR 2, and this is "the real-platform
  equivalent" of that — worth keeping as the project's own repeatable way to re-verify crash
  reporting whenever KSCrash or the mapper changes, until MOB-25's real sample app exists.
- Added to `FEATURES.md`'s "Manual verification checklist (pilot)" as item 6, consolidated
  there alongside feat-007/feat-008's pre-existing device-only checks (previously scattered
  between this file and `archive/epics/phase-1-wrap-up.md` — user asked for one list, not
  several).

**Blockers** — none. Feature closed.

**Not in scope (explicitly deferred, not gaps)**
- Hang detection (MOB-18, `Watchdog` monitor) — feat-010's requirement per `FEATURES.md`.
- Symbolication itself — Backend's job (docs/00 §11 decision table, M3); this feature's job
  ends at `binary_images` + UUID reaching the backend.

**Files added:** `Sources/APMKit/Crash/{CrashReporter,CrashUserInfoStore,CrashReportSource,
CrashReportMapper,CrashReportProcessor,CrashBreadcrumbEncoder}.swift`,
`Tests/APMKitTests/Crash/{CrashReporterTests,CrashReportMapperTests,CrashReportProcessorTests,
IOSCrashHarnessTests}.swift`.
**Files amended:** `Package.swift` (KSCrash dependency), `Sources/APMKit/APMKit.swift`
(`installCrashReporting`/`processPendingCrashReports`), `Sources/APMKit/Breadcrumbs/
BreadcrumbRingBuffer.swift` (`onAdd` hook), `Tests/APMKitTests/Breadcrumbs/
BreadcrumbRingBufferTests.swift` (+1 test), `CONSTITUTION.md` (+1 dated decision).
