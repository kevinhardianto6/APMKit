# feat-010 · Stability + Remote Control

- **Status:** ✅ done · closed 2026-08-29 · **Depends on:** feat-005, feat-009
- **Requirements:** main-thread hang detection (>2s), cold-start metric, remote config fetch
  (cached fallback) + kill switch (`enabled: false` disables SDK without app release), SDK
  self-health counters (events written vs sent vs dropped). MOB-18/19/20/21/27.
- **Done when:** kill switch disables SDK from server; hang events fire; self-health reported
  (tests). **Met** — kill switch verified with a combined capture-and-upload proof, not just
  per-component tests (see Decisions); hang detection verified live on a real iOS Simulator,
  not just with a fake observer; self-health counters wired into every write/drop/send path
  that exists in the SDK.

This is the last Phase 2 feature — closing it completes both Phase 1 and Phase 2 of the epic.
The last feature also being the one to introduce the kill switch is notable: it's the safety
valve the spec says is required "before rollout to other teams" (docs/01 §9), so from this
point on the SDK has an operational off switch for every team that adopts it.

## Self-health counters (MOB-27)

`Sources/APMKit/Stability/SelfHealthCounters.swift` — thread-safe (`NSLock`) `written`/`sent`/
`dropped` counters, `snapshot()` for read access. In-process introspection only, not a new
wire event type: docs/01 §4 defines no `self_health` event schema, so nothing here is sent to
the backend — a host app that wants to surface it (e.g. a debug overlay, MOB-26) reads
`SelfHealthCounters.shared.snapshot()`.

Wired at every point in the existing pipeline where an event's fate is actually decided:
- `DiskQueueEventSink`: a successful `enqueue` → `written`; a caught disk-write failure (the
  `try?` this used to swallow silently is now a real `do`/`catch`) → `dropped`.
- `FileDiskQueue.evictIfNeeded` (MOB-06's size/count cap): each evicted event → `dropped` —
  it was written, then genuinely lost before ever being sent. New optional `selfHealth`
  constructor param, default `.shared`, no behavior change for existing callers.
- `SyncEngine`: `.accepted` (202) → `sent`; `.rejected` (400) → `dropped` — docs/01 §7
  explicitly calls this one out: "Catat sebagai metrik internal."

An event can be both `written` and later `dropped` (eviction) — these are lifecycle counts,
not a partition that must sum to a fixed total.

## Remote config + kill switch (MOB-20/21)

`Sources/APMKit/Stability/{RemoteConfig,RemoteConfigFetcher,RemoteConfigStore,KillSwitch}.swift`
— full `GET /v1/config` (docs/01 §9) implementation.

- `RemoteConfig`: models the entire documented payload (`enabled`, `sampling`, `max_batch`,
  `upload_interval_s`, `disabled_features`). **Scope decision:** this feature only *acts on*
  `enabled`. `sampling` is MOB-22's own row (P1, not in this feature's `FEATURES.md` row);
  `max_batch`/`upload_interval_s` feeding into `SyncEngine.Configuration` is the same kind of
  decision — `CONSTITUTION.md`'s build order says out-of-scope ideas become new rows, not
  drive-by edits. Fields are still parsed and cached now (a config fetch is one atomic object;
  there's no reason to fail parsing over fields not yet acted on), just inert.
- `RemoteConfigFetcher`: real `GET /v1/config`, same anti-loop discipline as `IngestClient`
  (bare `URLSession`, no delegate, must never be `APM.instrumentedSession()`). `IngestEndpoint`
  gained a `configURL` computed property (sibling of `.../v1/ingest` under the same host, so
  MOB-10's anti-loop exclusion — by host, not path — covers it automatically).
- `RemoteConfigStore`: holds the current config for synchronous reads, seeded at `init` from
  a `UserDefaults` cache or `.safeDefault` (`enabled: true` — a fresh install that's never
  reached the config endpoint should behave like normal SDK operation, not silently disable
  itself). `apply(_:)` takes a fetch result; `nil` (any failure) leaves the existing value
  untouched — this is "cache lokal dan fallback ke default bila gagal" (docs/01 §9) in
  practice: the fetch (`APM.fetchRemoteConfig`) is a background operation that only ever
  *improves* on what's already synchronously available, never blocks on it.
- `KillSwitch: EventSink`: the outermost pipeline stage (wraps `Scrubber`, not the other way
  around) — drops everything without forwarding when `store.current.enabled == false`. Kill-
  switch drops are **not** counted via `SelfHealthCounters` — intentional operator suppression
  isn't an internal failure.
- `SyncEngine` gained an `isEnabled: () -> Bool` closure (default `{ true }`, no behavior
  change for existing callers), checked at the top of every sync cycle.

**User's explicit ask: "genuinely proven, not just unit-tested."** `KillSwitchTests
.killSwitchStopsCaptureAndUpload` is one test, one shared `RemoteConfigStore`, that: captures
an event while enabled (lands on disk) → flips the switch off → captures again (does NOT land
on disk) → triggers a real `SyncEngine` cycle (does NOT upload, data stays queued) → flips the
switch back on → captures again (lands) → triggers sync again (both queued events upload).
Through the real `KillSwitch`/`Scrubber`/`FileDiskQueue`/`SyncEngine` types, not fakes standing
in for them.

SEC-20 ("remote config may only toggle predefined flags, never change executable behavior") is
satisfied by construction: `RemoteConfig` is a fixed, predefined `Codable` shape; there is no
code path anywhere that executes anything the server sends.

## Cold-start metric (MOB-19)

`Sources/APMKit/Stability/ColdStartTracker.swift` — `duration_ms` = time from process start
(read via `sysctl`/`kinfo_proc.p_starttime`) to `recordFirstFrame(sink:sessionManager:)` being
called, emitted as `lifecycle`/`cold_start` (docs/01 §4.6).

**Deliberately host-invoked, not automatic — same reasoning as MOB-12's screen tracking**
(`ScreenTracking.swift`, docs/02 §3.4): the only automatic way to know "first frame drawn" is
swizzling `CALayer`/`UIViewController` display methods, which `CONSTITUTION.md` and MOB-12's
own precedent already reject (risk of crashing/undefined behavior, collision with other SDKs
doing the same swizzle — Firebase Analytics already swizzles `viewDidAppear` in this org's
apps per docs/02 §3.4's own footnote). The host calls `APM.recordFirstFrame(...)` once, from
wherever they consider "first frame" — typically a `CATransaction` completion block around the
initial screen's first layout. This is a real, non-zero-effort integration step, same
footnote-worthy status as MOB-12's (MOB-25 integration docs should call it out just as
prominently).

Idempotent (only the first call per process does anything) and defensive (a negative/garbage
duration — clock adjustment, failed `sysctl` read — is never emitted, not even as a wrong
value).

**No host-vs-macOS gap here, unlike most of this SDK's iOS-only bits:** `sysctl`/`kinfo_proc`
is genuinely portable Darwin API (the same mechanism `DeviceIntegrityDetector
.isDebuggerAttached` already uses), so `ColdStartTrackerTests.realProcessStartTimeIsPlausible`
exercises the *real* implementation on the macOS test host, not just a fake standing in for it.

## Hang detection (MOB-18)

`Sources/APMKit/Stability/{HangObserving,HangDetector}.swift` — main-thread hang >2s, reported
live as a `crash`/`crash_type: hang` event (docs/01 §4.3), `is_fatal: false`.

**Wraps KSCrash's own `Watchdog` monitor rather than hand-rolling a timer** — the same
"wrap a mature library, don't hand-roll" reasoning `CONSTITUTION.md`/docs/00 §11 decision 4
already applies to crash reporting generally. `CrashReporter.install()` now enables
`.watchdog` (deliberately excluded in feat-009 — see the dated `CONSTITUTION.md` decision,
"feat-010 turns it on," now fulfilled). KSCrash's Watchdog monitor is exactly "a timer
watching the main run loop" done safely: a `CFRunLoopObserver` on the main run loop plus a
dedicated high-priority watchdog *thread* running its own run loop with a repeating timer —
the main thread is only ever touched with a relaxed-ordering atomic timestamp write, never
blocked or locked. This SDK adds none of that machinery itself.

**Live observation, not the next-launch report pipeline.** `HangDetector` uses KSCrash's
documented `KSCrash.shared.addHangObserver(_:)` (a `Hang` category method, public Swift API)
to get `Started`/`Updated`/`Ended` callbacks with nanosecond timestamps, in-process, the
moment a hang resolves — completely separate from feat-009's `CrashReportProcessor`, which
handles *fatal* watchdog terminations (the OS actually kills the process, `0x8badf00d`) read
from disk on the next launch; `CrashReportMapper` already handled `crash_type: hang` there
defensively since feat-009. `HangDetector` only acts on `.ended` (final, resolved duration
known), filtered to `>= 2.0s` (the threshold is a constructor param; KSCrash's own internal
~250ms hang-detection threshold is unrelated — it only controls when `.started`/`.updated`
callbacks begin, not what this SDK reports). `kscm_watchdog_setReportsHangs` (KSCrash's own
persisted-report toggle for resolved hangs) is left at its default `false`: this SDK doesn't
need KSCrash to separately persist what it already captured live.

`HangObserving` protocol (mirrors feat-009's `CrashUserInfoStore`/`CrashReportSource` pattern)
wraps KSCrash's `addHangObserver` behind this SDK's own `HangChange` vocabulary — `HangDetector`
is fully unit-testable via a fake, no real Watchdog monitor needed for the threshold-filtering/
event-shape logic (`HangDetectorTests`, 6 tests).

**Real-runtime proof — the user's explicit safety concern.** The pure logic above is
macOS-testable, but "does the real Watchdog monitor + a real blocked main thread actually
produce this end-to-end, without the detector itself adding jank" is not. Added
`IOSCrashHarnessTests.phase3_hangDetection` (single self-contained test, unlike phase 1/2 —
a resolved hang doesn't crash the process, so no process split is needed): installs crash
reporting + starts hang detection, blocks the *real* main thread for 2.5s via
`DispatchQueue.main.async { Thread.sleep(...) }`, polls the disk queue. **Passed on Xcode
26.4 / iOS 18.0 Simulator in 2.75s** — the test completing at all (rather than hanging itself)
is direct proof the detector doesn't block the thread it's watching. Also re-ran
`phase1_forceCrash`/`phase2_readBackAfterRelaunch` after adding `.watchdog` to confirm no
regression to the existing crash pipeline.

## Blockers — none. Feature closed.

## Not in scope (explicitly deferred, not gaps)
- MOB-22 (sampling) — `RemoteConfig.sampling` is parsed and cached but not enforced; its own
  `FEATURES.md` row if/when picked up.
- Wiring `RemoteConfig.maxBatch`/`.uploadIntervalSeconds` into `SyncEngine.Configuration` —
  same reasoning as MOB-22, a deliberate scope line, not an oversight.
- SEC-14 (key rotation via remote config) — not in this feature's requirement list
  (MOB-18/19/20/21/27 only); the fetch mechanism built here could support it, but nothing
  currently reads/acts on a key field.

**Files added:** `Sources/APMKit/Stability/{SelfHealthCounters,RemoteConfig,
RemoteConfigFetcher,RemoteConfigStore,KillSwitch,ColdStartTracker,HangObserving,
HangDetector}.swift`, `Tests/APMKitTests/Stability/{SelfHealthCountersTests,RemoteConfigTests,
KillSwitchTests,ColdStartTrackerTests,HangDetectorTests}.swift`.
**Files amended:** `Sources/APMKit/Storage/{DiskQueueEventSink,FileDiskQueue}.swift`
(self-health hooks), `Sources/APMKit/Sync/SyncEngine.swift` (self-health + kill-switch gate),
`Sources/APMKit/IngestEndpoint.swift` (`configURL`), `Sources/APMKit/Crash/CrashReporter.swift`
(`.watchdog` monitor), `Sources/APMKit/APMKit.swift` (`startHangDetection`,
`fetchRemoteConfig`, `recordFirstFrame`), `Tests/APMKitTests/Storage/FileDiskQueueTests.swift`
and `Tests/APMKitTests/Sync/SyncEngineTests.swift` (self-health/kill-switch assertions added
to existing tests), `Tests/APMKitTests/Crash/IOSCrashHarnessTests.swift` (+`phase3_hangDetection`).
