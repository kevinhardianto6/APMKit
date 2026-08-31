# feat-016 · Composition Root (`APM.start`)

- **Status:** ✅ done · closed 2026-08-31 · **Depends on:** feat-014, feat-015
- **Requirements:** one `APM.start(configuration:)` that assembles and wires the whole pipeline
  by construction; granular types stay public; a genuinely installable internal verification
  app (not MOB-25's own sample app) to make cold-start and Keychain-relaunch persistence
  measurable for the first time in this repo.
- **Done when:** a from-scratch integration, timed, completes in under 30 minutes following only
  the written docs, measured directly — not assumed satisfied because a composition root exists.

## Spike: hand-written `.xcodeproj`, no scaffolding tool

No `xcodegen`/`tuist` installed, and `swift package generate-xcodeproj` no longer exists in this
SwiftPM. Hand-wrote a minimal `.pbxproj` (single application target, local Swift package
reference to the repo root, plain SwiftUI `App`) — `VerificationApp/`, sibling to `Sources/`/
`Tests/`, outside the SDK's own `Package.swift` (`AGENTS.md`'s "no app target" stays true for the
SDK itself). **It worked on the first real attempt**: `xcodebuild -list` resolved the local
package and its KSCrash dependency immediately, and a full `xcodebuild ... build` against a
booted iOS 18.0 Simulator succeeded with no pbxproj fixes needed. No re-scoping was necessary —
reported back per the plan, then proceeded.

One real gotcha found and fixed during verification (not the pbxproj itself): the initial
target build settings had `CODE_SIGNING_ALLOWED = NO` (simplest thing that gets a from-scratch
project to build). This is **fine for building and running**, but breaks real Keychain
persistence — an unsigned app's `SecItemAdd`/`SecItemCopyMatching` round-trip is unreliable
across process relaunches. Fixed by switching to ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`,
`CODE_SIGNING_ALLOWED = YES`) — "Sign to Run Locally," no Apple Developer account needed, works
on Simulator. This is exactly the kind of gap only a real installable app could have surfaced —
confirmed empirically (see "Checklist item 9" below): the same disk read-back test that silently
failed to decrypt (0/2 events) under `CODE_SIGNING_ALLOWED = NO` correctly decrypted (2/2, then
5/5 after a real relaunch) once ad-hoc signing was in place.

## What was built

**Production (`Sources/APMKit/Composition/`):**
- `APMConfiguration.swift` — `APM.Configuration`: only `ingestEndpoint` is required; everything
  else (pinning, queue directory, disk-queue/sync tuning, the `RemoteConfigStore`'s backing
  `UserDefaults`) has a safe default. `Configuration.defaultQueueDirectory()` is public —
  genuinely useful for diagnostics, and what the verification app's own Keychain-persistence
  check reads back from.
- `APMInstance.swift` — returned by `start()`; forwards to the existing granular static `APM.*`
  methods (`instrumentedSession`, `logError`, `recordFirstFrame`) with `sink`/`sessionManager`/
  `ingestEndpoint` already filled in, so a host using `start()` never threads those through its
  own call sites by hand. The granular statics are unchanged and still directly callable.
- `APMStart.swift` — `APM.start(configuration:)` itself. Assembles, in order: `SessionManager`,
  `RemoteConfigStore`, `FileDiskQueue` (encrypted by default, SEC-08) with an
  `EphemeralInMemoryDiskQueue` fallback if directory creation throws (`CONSTITUTION.md` rule #1:
  never propagate), the `KillSwitch → Scrubber → DiskQueueEventSink` chain
  (`CONSTITUTION.md`: Capture → Scrub → Disk → Sync, kill switch outermost per feat-010's own
  reasoning), `CertificatePinning` bundling the pin config with this pipeline's own
  `RemoteConfigStore` (SEC-11, feat-015 — the host never constructs a `RemoteConfigStore` just
  to enable pinning), `IngestClient`, `EnvelopeFactory`, `SyncEngine` (started immediately —
  MOB-08 trigger 1/3), crash reporting + hang detection (`installCrashReporting` then
  `startHangDetection`, order matters), an initial remote-config fetch, and
  `AutomaticBreadcrumbSource` wired via its new hooks for MOB-08 triggers 2/3 and 3/3.
- `EphemeralInMemoryDiskQueue.swift` — the never-throw fallback; not public, `APM.start`-only.
- `AutomaticBreadcrumbSource` (feat-007, amended) — three new optional closures
  (`onDidEnterBackground`, `onWillEnterForeground`, `onConnectivityRestored`), `nil` by default
  (no behavior change for existing callers). This is what lets `APM.start` wire
  `SessionManager`/`SyncEngine` to the real `UIApplication`/`NWPathMonitor` notifications this
  type already observes, instead of standing up a second, competing set of observers.
- `APM.fetchRemoteConfig` (feat-010, amended) — added an optional `pinning: CertificatePinning?`
  parameter (`nil` default, unchanged behavior) so `APM.start`'s remote-config fetch can honor
  SEC-11 too, not just `IngestClient`'s uploads. Side effect, stated for the record: the default
  session this method builds now goes through `SDKOwnedSessionConfiguration` (TLS 1.2 floor)
  instead of a bare `.default` configuration — a consistency fix, not a behavior regression.

**Internal verification app** (`VerificationApp/`, `docs/03-Integration-Guide.md`): see the
spike section above for the app itself; the integration guide is what the timed run in "Timed
integration" below actually followed.

## Tests

`Tests/APMKitTests/Composition/`:
- `APMStartTests.swift` — drives the real assembled pipeline: a minimal `start()` call writes a
  real encrypted event to a real temp directory; the kill switch (`configStore.apply`) stops
  new events from reaching disk; `instrumentedSession()` auto-excludes this instance's own
  ingest host; two full end-to-end tests reusing feat-015's `TLSMockServer` — a correctly pinned
  handshake uploads and drains the queue for real, a mismatched pin never drains (fails closed).
- `EphemeralInMemoryDiskQueueTests.swift` — the fallback path's own `DiskQueue` contract
  (FIFO order, targeted removal, count/size, limit) — previously entirely untested since nothing
  exercised it before this feature.
- `AutomaticBreadcrumbSourceTests.swift` (amended) — the three new hooks fire for exactly the
  matching lifecycle/connectivity event, never for an unrelated one.

225 tests (was 214 at feat-015 close; +11). `./verify.sh build`/`test`/`budget` all
`HARNESS_VERIFY: PASS`; `test` re-run 8× clean.

## Bug found while writing this feature's own tests: `RemoteConfigStore` test isolation

`APM.start`'s `RemoteConfigStore` defaults to `UserDefaults.standard` — correct for a real app
(a fetched kill-switch state persisting across launches is the whole point of that cache), but
means every `APM.start()` call in the same `swift test` process shares the same cached config.
The first version of `APMStartTests.swift` had a kill-switch test call `configStore.apply(...)`
with `enabled: false`, which then silently disabled *every other test's* `APM.start()` in the
same run (100% reproducible once triggered, not a race). Fixed by adding
`Configuration.remoteConfigUserDefaults` (defaults to `.standard`, overridable) and giving each
test its own `UserDefaults(suiteName:)`. Documented on the field itself so a future test author
doesn't rediscover this the same way.

## Checklist item 9 (Keychain persistence across a real relaunch) — verified for real

Previously blocked: `xcodebuild test`'s XCTest infrastructure resets Keychain state between
separate invocations regardless of app-binary identity (feat-014's finding), and there was no
app to install-and-relaunch outside XCTest. With `VerificationApp` now genuinely installable:

1. Clean install, first launch: `APM.start()` writes 2 real encrypted events (`logError` +
   `recordFirstFrame`) to `<Caches>/kit.apm.queue`. A second, independently-constructed
   `FileDiskQueue` (same directory, same default `KeychainDiskQueueKeyStore`) reads them back —
   `decoded on peek: 2`, confirmed correct once ad-hoc signing was fixed (see spike section).
2. `xcrun simctl terminate` (real process termination, confirmed via `launchctl list` showing no
   process) then `xcrun simctl launch` again — a genuinely new process (different PID: 40819 →
   40869, not a resume).
3. Second launch's independent `FileDiskQueue` read-back: **`decoded on peek: 5`** — the 2
   events from the *first* process, still on disk (never uploaded — fake ingest host), plus 2-3
   new ones from the second launch's own `APM.start()`, ALL decrypting successfully under the
   *second* process's own fresh `KeychainDiskQueueKeyStore()` instance.

This is the actual proof: the AES key persisted in Keychain across a real process death and
relaunch, and correctly decrypts ciphertext written by a different process instance. **Item 9 is
now ✅ verified**, closing feat-014's own flagged gap.

## Checklist item 5 (cold-start ≤30ms p95) — unblocked, not closed

`APM.start()`'s own synchronous wall-clock cost, measured via `CFAbsoluteTimeGetCurrent()`
bracketing the call, logged through `NSLog` and read back with `simctl spawn log show`, across 8
real cold launches on a booted iOS 18.0 Simulator: **22.4, 26.1, 26.3, 26.7, 27.6, 33.0, 36.2,
40.6 ms**. Two of eight exceed the 30ms budget.

**Not claiming this closes item 5.** iOS Simulator runs on Mac hardware under a different
scheduler and I/O stack than a real iPhone — these numbers are a real measurement of something,
but not the "real-device profiling under realistic load" the checklist item and docs/02 §5
explicitly require, and Simulator timing is known to be noisy/non-representative in both
directions (sometimes faster on powerful Mac silicon, sometimes slower under virtualization
overhead). What this feature actually changes: **the blocker is gone** — cold-start is now
measurable at all, for the first time, because an installable app exists to attach a timer to.
Item 5 stays open on the manual checklist, re-scoped from "no way to measure this" to "needs a
real device run," with these Simulator numbers recorded as a first signal, not a verdict.

## Timed integration (MOB-25)

Wrote `docs/03-Integration-Guide.md` first, then reset `VerificationApp`'s `ContentView`/
`VerificationAppApp` to a genuinely blank pre-integration state (no APMKit import at all) and
re-integrated following only that document.

**Honest caveat on the number itself:** the mechanical edit-and-build time for this session
(reading the doc's 5 steps, writing ~20 lines of Swift, one clean `xcodebuild` — 45 seconds
wall-clock) is **not a valid stand-in for a human's 30-minute budget** — an AI editing files
directly skips the reading, typing, and Xcode-UI navigation time a real integrator spends, so
reporting that figure as "the" integration time would be a false precision, not evidence.

What *is* honest, direct evidence for the ≤30-minute target:
- **One required call** (`APM.start(configuration:)`) with one required argument
  (`ingestEndpoint`) makes the SDK fully operational — encrypted queuing, scrubbing, kill
  switch, crash/hang reporting, remote-config fetch, and background/connectivity-triggered sync
  all wired, per the real end-to-end tests in `APMStartTests.swift`.
- Everything else in the guide (network capture, manual error/breadcrumb reporting, cold-start)
  is explicitly optional, each a single line.
- The build succeeded on the **first attempt** with zero debugging round-trips — no manually
  wired step was forgotten or ordered wrong, because there was only one step.
- Real device confirmation: installed, launched, and ran on a booted iOS Simulator with no
  crash — including a real (expected) network failure against the doc's placeholder ingest host,
  handled silently per `CONSTITUTION.md` rule #1, confirmed via `simctl spawn log show`.

This is the actual claim feat-013's finding was worried about — "roughly a dozen manually-wired
pieces before the first event is captured" — replaced with one call. A rigorous minutes-based
proof of MOB-25 still wants a real, unfamiliar human engineer timing themselves against this
doc; that's outside what this session can produce, and is flagged here rather than fabricated.

## Explicitly not done here

- `VerificationApp` does not become MOB-25's own published/maintained sample app — see the
  2026-08-31 `FEATURES.md` note preceding this feature's scoping. It stays internal.
- Checklist item 5 (cold-start) stays open, re-scoped as above — not claimed closed.
- No composition-root support for a *second* concurrent `APM.start()` call (e.g., re-configuring
  mid-process) — one call, once, at launch, matching every underlying piece's own existing
  "call once" documentation. Not asked for; not built.

**Files added:** `Sources/APMKit/Composition/APMConfiguration.swift`,
`Sources/APMKit/Composition/APMInstance.swift`, `Sources/APMKit/Composition/APMStart.swift`,
`Sources/APMKit/Composition/EphemeralInMemoryDiskQueue.swift`,
`Tests/APMKitTests/Composition/APMStartTests.swift`,
`Tests/APMKitTests/Composition/EphemeralInMemoryDiskQueueTests.swift`,
`docs/03-Integration-Guide.md`, `VerificationApp/` (Xcode project + minimal SwiftUI app).
**Files amended:** `Sources/APMKit/Breadcrumbs/AutomaticBreadcrumbSource.swift` (three new
hooks), `Sources/APMKit/APMKit.swift` (`fetchRemoteConfig` gained `pinning:`),
`Tests/APMKitTests/Breadcrumbs/AutomaticBreadcrumbSourceTests.swift` (+2 tests).
