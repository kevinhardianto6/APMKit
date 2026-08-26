# feat-003 · Network Capture

> **Amended 2026-08-24 under feat-004's review** (see `archive/features/feat-004.md`):
> `NetworkCaptureDelegate` now also captures the raw query string (appended to `path`) and
> raw request/response headers (`req_headers`/`res_headers`), so SEC-02/03 have live data to
> filter. Capture stays raw/unfiltered by design — `Scrubber` is the sole enforcement point.

- **Status:** ✅ done · closed 2026-08-24 · **Depends on:** feat-001, feat-002
- **Requirements:** `URLSessionTaskDelegate` + `URLSessionTaskMetrics`; per-phase timings
  (DNS/TCP/TLS/TTFB); map `NSURLError` → `failure_category` (`01` §5), distinguishing a
  pinning-rejection `NSURLErrorCancelled` from a normal cancel →`ssl_pinning_rejected`.
  Expose `APM.instrumentedSession()` + a forwardable delegate. MOB-01/02/03/10, MOB-02b
  (added 2026-08-24 — 4xx/5xx responses emit both a `network` event and a
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
Committed as `e8abf08` — `feat-003: Network Capture` (rewritten from `b4eb383`/`0a6be2b` to
drop a Co-Authored-By trailer; content identical).

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
