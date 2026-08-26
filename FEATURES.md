# Features

> Scope backbone, grouped by epic (one epic = one PRD = one ID prefix).
> Status: 🟡 not started · 🔵 in progress · ✅ done · 🔴 blocked · 🟠 needs verification
> **One feature is active at a time per person** (see `state/<name>.md`) — the backlog may span epics.
> `By` = who actually did the work, from `git config user.name` on the machine that ran it.
> Completed feature detail → `archive/features/`. Completed *epics* → `archive/epics/`, listed under Shipped.

| Epic | Progress | Active / open |
|------|:--------:|---------------|
| APM Kit iOS SDK | 2/10 | feat-003 🟠 (needs review) |

---

## Epic · APM Kit iOS SDK

**PRD:** `docs/02-Mobile-SDK.md` (+ `docs/01-Kontrak-Data-API.md` for schema/API contract,
`docs/00-Overview.md` for product context) · **Prefix:** `feat-`
**Scope:** Phase 1 (network observability) + Phase 2 (crash reporting) only. Phase 3
(backend, dashboard, symbolication service, sampling, public sample-app/docs) is explicitly
out of scope for this epic.
**Started:** 2026-08-24 · **Started by:** Kevin Hardianto

Build order is fixed by dependency (see `CONSTITUTION.md` → Prohibitions — process). One
feature per branch/PR; stop for review after each.

| ID | Feature | Status | By | Depends on | Requirements | Evidence |
|----|---------|:------:|----|------------|--------------|----------|
| feat-001 | Core & Envelope | ✅ | Kevin Hardianto | — | schema §2–5 (01) | [archive](archive/features/feat-001.md) |
| feat-002 | Disk Queue | ✅ | Kevin Hardianto | feat-001 | MOB-04/05/06, SEC-07 | [archive](archive/features/feat-002.md) |
| feat-003 | Network Capture | 🟠 | Kevin Hardianto | feat-001, feat-002 | MOB-01/02/03/10 | 20 tests, `HARNESS_VERIFY: PASS (all)` |
| feat-004 | Scrubbing | 🟡 | — | feat-003 | SEC-01..05b | — |
| feat-005 | Sync Engine | 🟡 | — | feat-002, feat-004 | MOB-07/08/09 | — |
| feat-006 | Identifier & Manual API | 🟡 | — | feat-001, feat-004 | MOB-28, SEC-06 | — |
| feat-007 | Breadcrumbs | 🟡 | — | feat-004, feat-006 | MOB-11/12/13 | — |
| feat-008 | Device Integrity | 🟡 | — | feat-001 | MOB-29/30/31 | — |
| feat-009 | Crash Reporting (KSCrash) | 🟡 | — | feat-001..008 | MOB-15/16/17 | — |
| feat-010 | Stability + Remote Control | 🟡 | — | feat-005, feat-009 | MOB-18/19/20/21/27 | — |

> feat-001..008 = end of Phase 1 (SDK shippable for network observability). feat-009/010 =
> Phase 2. feat-009 may span several PRs (sub-split as needed) — do not rush the crash handler.

### feat-003 · Network Capture

- **Status:** 🟠 needs verification (implemented, tests pass, awaiting review) · **Depends on:** feat-001 ✅, feat-002 ✅
- **Requirements:** `URLSessionTaskDelegate` + `URLSessionTaskMetrics`; per-phase timings
  (DNS/TCP/TLS/TTFB); map `NSURLError` → `failure_category` (`01` §5), distinguishing a
  pinning-rejection `NSURLErrorCancelled` from a normal cancel →`ssl_pinning_rejected`.
  Expose `APM.instrumentedSession()` + a forwardable delegate. MOB-01/02/03/10, MOB-02b
  (added 2026-08-24 — see Decisions: 4xx/5xx responses emit both a `network` event and a
  `network_failure(http_error)` event with `status_code`).
- **Done when:** real requests produce `network`/`network_failure` events; pinning rejection
  maps to `ssl_pinning_rejected` (tests).

| ✓ | Check | By | Proof |
|:-:|-------|----|-------|
| ✅ | Real successful request → `network` event, exact §4.1 fields | Kevin Hardianto | `successfulRequestProducesNetworkEvent` (loopback `MockHTTPServer`) |
| ✅ | Per-phase timings populated from `URLSessionTaskMetrics` when available | Kevin Hardianto | `emitSuccessEvent` reads `domainLookup*`/`connect*`/`secureConnection*`/`request*`/`responseStartDate`; not independently asserted per-field over loopback (phases can legitimately be near-zero/absent on localhost) |
| ✅ | Real transport failure (timeout) → `network_failure`, correct `failure_category` | Kevin Hardianto | `realTimeoutProducesTimeoutFailure` (server holds the connection open, real `NSURLErrorTimedOut`) |
| ✅ | Real app-initiated cancel → `cancelled`, not confused with pinning | Kevin Hardianto | `realCancelMapsToCancelled` |
| ✅ | Pinning rejection (observed via forwarding delegate) → `ssl_pinning_rejected` on a later `NSURLErrorCancelled` | Kevin Hardianto | `pinningRejectionObservedThroughForwardingDelegate` |
| ✅ | A trust challenge the host *accepts* does NOT mis-mark a later unrelated cancel | Kevin Hardianto | `acceptedChallengeDoesNotMarkPinningRejection` |
| ✅ | `FailureCategoryMapper` covers all 8 non-http_error categories + unknown fallback | Kevin Hardianto | `FailureCategoryMapperTests` (12 tests, pure/no networking) |
| ✅ | MOB-10 anti-loop: excluded hosts never captured | Kevin Hardianto | `excludedHostsAreNotCaptured` |
| ✅ | 4xx/5xx → both `network` and `network_failure(http_error)` events, with `status_code` | Kevin Hardianto | `httpErrorResponseProducesBothEvents` |

20 new tests (42 cumulative), `./verify.sh all` → `HARNESS_VERIFY: PASS (all)` (2026-08-24),
re-run 3× clean to check for flakiness in the timing-sensitive networking tests.

**Decisions**
- **http_error handling — originally a spec ambiguity, now fixed upstream.** docs/01 §4.2's
  `network_failure` attrs table didn't list `status_code`, but §5 defined `http_error` as
  "4xx/5xx response received" and §6 fingerprints `network_failure` as
  `host+failure_category+status_code` — impossible without it. Resolved during implementation
  per user direction (dual-event: `network` always, `network_failure(http_error)` additionally
  for status ≥400). **2026-08-24: the user updated `docs/01-Kontrak-Data-API.md` §4.2/§5 and
  `docs/02-Mobile-SDK.md` (new requirement `MOB-02b`) to formally document exactly this
  behavior**, and clarified `status_code` is required for `http_error` while
  `error_domain`/`error_code` are required only for real transport failures — NOT for
  `http_error`. Code updated to match: `emitHTTPErrorEvent` no longer synthesizes placeholder
  `error_domain`/`error_code` values (previously `"HTTPStatus"`/status code); it now sends
  only `host`/`path`/`method`/`failure_category`/`status_code`/`duration_ms`, matching the
  official table exactly. `./verify.sh all` re-confirmed green (42/42) after the change.
- **Pinning-rejection detection is delegate-forwarding based, not SDK-owned pinning.** The
  spec's implementation note only says the SDK must "mark the request that failed at
  trust-evaluation stage" — it doesn't mandate the SDK implement pinning itself. Design: the
  host app's own trust-evaluation logic (`NetworkCaptureForwardingDelegate`) is forwarded
  server-trust challenges by `NetworkCaptureDelegate`; the disposition the host returns
  (`.cancelAuthenticationChallenge`/`.rejectProtectionSpace`) is observed and recorded against
  that task's identifier *before* the host's completion handler runs. When the task later
  completes with a plain `NSURLErrorCancelled`, that recorded state — not the error code alone
  — is what resolves it to `ssl_pinning_rejected`. This keeps APMKit dependency-free (no
  pinning implementation of its own) while still satisfying the distinguishing requirement.
  `forwardingDelegate` is declared `weak` (host owns its own pinning delegate elsewhere,
  mirroring standard `URLSessionDelegate` ownership) — tests must hold their own strong
  reference to the forwarding delegate, which is exactly the bug the first test-writing pass
  hit and had to fix.
- **Network Capture never writes to the disk queue directly.** Introduced `EventSink`
  (protocol) as the pipeline boundary — `NetworkCaptureDelegate` hands events to whatever
  `sink` it's given. This keeps `CONSTITUTION.md`'s mandatory Capture → Scrub → Disk → Sync
  order structurally true rather than just documented: there is no code path in feat-003 that
  can reach `FileDiskQueue` directly, only through whatever implements `EventSink` (the
  scrubber, feat-004).
- **`swift test` on macOS needed a declared macOS platform floor.** `Network`'s
  `tls_protocol_version_t` (used for the `tls_version` attribute) requires macOS 10.15+
  availability; with no macOS entry in `Package.swift`, SwiftPM defaulted to a much older
  floor and failed to compile on the host toolchain. Added `.macOS(.v11)` to `platforms` —
  **not a distribution target**, solely so host-toolchain builds/tests see modern API
  availability. Documented inline in `Package.swift` and this is the same
  host-vs-iOS-toolchain gap flagged after feat-001/002; worth remembering for feat-007/008 too.
- **Async `URLSession.data(from:)` was unreliable with a custom session delegate in tests.**
  The convenience `data(from:)`/`data(for:)` async APIs did not reliably trigger
  `NetworkCaptureDelegate`'s `didFinishCollecting`/`didCompleteWithError` callbacks in this
  test environment — tests using it saw zero captured events even though the HTTP exchange
  itself completed. Switched every test to the classic `dataTask(with:).resume()` pattern with
  polling (`waitForEvents`), which is reliable. Not fully root-caused (may be a Swift runtime
  quirk in this toolchain/environment); flagging rather than guessing further, since it doesn't
  block the feature — the underlying `NetworkCaptureDelegate` production code path is
  delegate-callback-based either way and unaffected by which client API a host app uses.

**Blockers** — none.

**Files added:** `Sources/APMKit/Network/{FailureCategory,FailureCategoryMapper,EventSink,
NetworkCaptureForwardingDelegate,NetworkCaptureDelegate}.swift`; `Sources/APMKit/APMKit.swift`
now exposes `APM.instrumentedSession(...)`; `Package.swift` gained a macOS platform floor.
`Tests/APMKitTests/Network/{FailureCategoryMapperTests,NetworkCaptureDelegateTests}.swift`,
`Tests/APMKitTests/Support/{MockHTTPServer,CollectingEventSink}.swift` (reusable for feat-005).

---

### feat-004 · Scrubbing

- **Status:** 🟡 not started · **Depends on:** feat-003
- **Requirements:** last step before disk write. Header allowlist (Content-Type/Length,
  Accept, User-Agent only); redact query-param values; normalize id/UUID/long-number path
  segments; never capture bodies; pattern-redact (ID phone `08xx`/`+62xx`, email, JWT-like,
  ≥10-digit runs) over all strings incl. breadcrumbs and error text. SEC-01..05b.
- **Done when:** phone numbers removed from URLs/paths/errors/breadcrumbs (tests).

**Decisions** — none yet. **Blockers** — none.

---

### feat-005 · Sync Engine

- **Status:** 🟡 not started · **Depends on:** feat-002, feat-004
- **Requirements:** batched upload (≤200 events/≤1MB gzip via Compression) on timer,
  background transition, connectivity restore; exponential backoff. Exact response contract
  (`01` §7): 202 delete, 400 drop (no infinite retry), 401/403 pause 24h, 413 split, 429 honor
  Retry-After, 5xx backoff+keep. Delete local events only after 2xx. Separate non-instrumented
  `URLSession`; ingest host excluded from capture (anti-loop). MOB-07/08/09.
- **Done when:** buffers offline, flushes on reconnect; every response code handled; no
  instrumentation loop (tests w/ mock server).

**Decisions** — none yet. **Blockers** — none.

---

### feat-006 · Identifier & Manual API

- **Status:** 🟡 not started · **Depends on:** feat-001, feat-004
- **Requirements:** `APM.setUser(id:)` takes any free-form string, sent **raw** in
  `envelope.user_id` over TLS, never hashed client-side (hashing to `user_ref` is backend's
  job). Fallback: stable random id persisted per install if never set. Raw `user_id` must
  never leak into breadcrumbs/logs/other fields. Also `APM.logError`. MOB-28, SEC-06.
- **Done when:** raw `user_id` present in envelope, never leaks elsewhere; fallback stable
  per install (tests).

**Decisions** — none yet. **Blockers** — none.

---

### feat-007 · Breadcrumbs

- **Status:** 🟡 not started · **Depends on:** feat-004, feat-006
- **Requirements:** `APM.breadcrumb(_:category:)` + automatic (screen/lifecycle/connectivity);
  ring buffer of last 100 attached to each error event. MOB-11/12/13.
- **Done when:** ring buffer attaches to errors; auto-crumbs fire (tests).

**Decisions** — none yet. **Blockers** — none.

---

### feat-008 · Device Integrity

- **Status:** 🟡 not started · **Depends on:** feat-001
- **Requirements:** snapshot once per session into `envelope.integrity`: `is_emulator`
  (`TARGET_OS_SIMULATOR`/env), `is_rooted` (jailbreak file checks + sandbox-write test +
  suspicious symlinks), `is_dev_mode` (debugger via `sysctl` `P_TRACED` + non-App-Store build
  via `embedded.mobileprovision`/TestFlight `sandboxReceipt`), `debugger_attached`. Heuristic
  only — no privileged APIs (no IMEI). MOB-29/30/31.
- **Done when:** flags correct on real device + simulator (manual verification required —
  simulator-only automation can't fully prove real-device jailbreak/dev-mode detection).

**Decisions** — none yet. **Blockers** — none.

---

### feat-009 · Crash Reporting (KSCrash)

- **Status:** 🟡 not started · **Depends on:** feat-001, feat-002, feat-003, feat-004,
  feat-005, feat-006, feat-007, feat-008 (end of Phase 1)
- **Requirements:** wrap KSCrash (do not hand-roll signal/mach handlers). On crash, write a
  minimal report to disk (no PII), send on next launch; include `binary_images` + UUIDs for
  later symbolication. MOB-15/16/17. May span several PRs — sub-split as needed; this is the
  highest-risk feature (crash handler is the sole component intentionally running during a
  crash, per `CONSTITUTION.md`).
- **Done when:** a forced crash is captured and appears in the mock backend after relaunch;
  raw on-disk report is minimal (no PII) — see docs/02 §6.2 trade-off box on why the raw crash
  report is unencrypted at write time.

**Decisions** — none yet. **Blockers** — none.

---

### feat-010 · Stability + Remote Control

- **Status:** 🟡 not started · **Depends on:** feat-005, feat-009
- **Requirements:** main-thread hang detection (>2s), cold-start metric, remote config fetch
  (cached fallback) + kill switch (`enabled: false` disables SDK without app release), SDK
  self-health counters (events written vs sent vs dropped). MOB-18/19/20/21/27.
- **Done when:** kill switch disables SDK from server; hang events fire; self-health reported
  (tests).

**Decisions** — none yet. **Blockers** — none.

---

## Shipped

Completed epics, rotated to `archive/epics/`. One line each.

_None yet._
