# feat-005 · Sync Engine

- **Status:** ✅ done · closed 2026-08-24 · **Depends on:** feat-002, feat-004
- **Requirements:** batched upload (≤200 events/≤1MB gzip via Compression) on timer,
  background transition, connectivity restore; exponential backoff. Exact response contract
  (`01` §7): 202 delete, 400 drop (no infinite retry), 401/403 pause 24h, 413 split, 429 honor
  Retry-After, 5xx backoff+keep. Delete local events only after 2xx. Separate non-instrumented
  `URLSession`; ingest host excluded from capture (anti-loop). MOB-07/08/09.
- **Done when:** buffers offline, flushes on reconnect; every response code handled; no
  instrumentation loop (tests w/ mock server).

| ✓ | Check | By | Proof |
|:-:|-------|----|-------|
| ✅ | 202 → batch deleted from disk | Kevin Hardianto | `acceptedDeletesBatch` |
| ✅ | 400 → batch dropped, never retried | Kevin Hardianto | `rejectedDropsBatch` |
| ✅ | 401/403 → data kept, sending paused 24h (`pauseDurationSeconds`) | Kevin Hardianto | `unauthorizedPausesAndKeepsData` |
| ✅ | 413 → batch split in half, retried | Kevin Hardianto | `payloadTooLargeSplitsBatch` (10 events → uploads of 10, 5, 5) |
| ✅ | 429 → honors `Retry-After` when present, falls back to backoff when absent | Kevin Hardianto | `rateLimitedHonorsRetryAfter`, `rateLimitedWithoutRetryAfterUsesBackoff` |
| ✅ | 5xx → exponential backoff (doubles each failure, capped), data kept | Kevin Hardianto | `serverErrorBacksOffExponentially` |
| ✅ | Transport failure (offline) → treated like 5xx, data kept | Kevin Hardianto | `transportFailureBacksOffAndKeepsData` |
| ✅ | Buffers offline, flushes on reconnect | Kevin Hardianto | `buffersOfflineFlushesOnReconnect` (same engine, same clock — advances past the backoff window it's actually under, then calls `connectivityRestored()`) |
| ✅ | `appDidEnterBackground()` also triggers a cycle | Kevin Hardianto | `backgroundTransitionTriggersSync` |
| ✅ | Real `POST /v1/ingest`: exact headers (`X-APM-Key`, `X-APM-Sdk`, `Content-Type`, `Content-Encoding: gzip`), body is valid gzip decoding back to the exact envelope | Kevin Hardianto | `IngestClientTests.sendsCorrectRequestShape` (real `MockHTTPServer`, real gzip round-trip via `GunzipHelper`) |
| ✅ | Every §7 status code maps to the right `UploadOutcome`, incl. `Retry-After` parsing | Kevin Hardianto | `IngestClientTests.mapsEveryStatusCode` (202/400/401/403/413/429/500/503 in one parametrized pass) |
| ✅ | MOB-09 anti-loop: uploader's default session has no delegate (structurally cannot be captured) | Kevin Hardianto | `uploaderSessionHasNoDelegate` |
| ✅ | MOB-09/10 anti-loop: `instrumentedSession()` excludes its own `ingestEndpoint` host AUTOMATICALLY — no manual `excludedHosts` step | Kevin Hardianto | `ingestHostIsExcludedAutomatically` (real request straight at the ingest host, zero captured events, `additionalExcludedHosts` deliberately left empty) |
| ✅ | `GzipEncoder` produces real RFC 1952 gzip (magic bytes, round-trips text and real envelope JSON, compresses meaningfully) | Kevin Hardianto | `GzipEncoderTests` (5 tests) |
| ✅ | `CRC32` matches the standard `"123456789"` → `0xCBF43926` test vector | Kevin Hardianto | `CRC32Tests` (3 tests) |

26 tests total (97 cumulative), `./verify.sh all` → `HARNESS_VERIFY: PASS (all)` (2026-08-24),
re-run 3× clean.

**Review history:** user approved response-contract coverage and the delegate-less ingest
session on first pass, with one required follow-up (below) before final sign-off, and
accepted the byte-cap decision as-is.

**Decisions**
- **No direct API exists for Apple gzip.** `Compression` framework has no gzip algorithm
  constant — `compression_encode_buffer` with `COMPRESSION_ZLIB` produces *raw* DEFLATE (no
  zlib or gzip framing, despite the name). Hand-rolled RFC 1952 gzip framing around it (10-byte
  header + raw deflate + CRC-32 + size trailer) — the standard workaround, not a shortcut;
  verified with a from-scratch `GunzipHelper` (test-only) that strips the framing, inflates,
  and checks the CRC-32/size trailer against the result. Hit and fixed a real bug in that
  helper during development: `Data` subsequence `.load(as: UInt32.self)` crashed with
  "misaligned raw pointer" (Data slices aren't guaranteed 4-byte aligned) — replaced with
  manual little-endian byte assembly.
- **`IngestUploading` bridges an async completion-handler API back to synchronous flow with a
  semaphore** inside `SyncEngine`'s private serial `workQueue`. Deliberate: this queue only
  ever runs sync cycles sequentially, is never the main queue, and nothing else waits on it —
  blocking it while a request is in flight is exactly the intended behavior (one batch upload
  completes before the next begins), not a main-thread violation of the perf budget.
- **The byte cap (§7: "maksimum 1 MB terkompresi") is not pre-checked client-side** — accepted
  as-is by the user. Only the 200-event cap is enforced proactively. Estimating compressed
  size before compressing is inaccurate, and actually compressing just to measure would
  duplicate `IngestClient`'s work. The `413` response is already docs/01's own defined
  mechanism for "batch too big" — relying on it (split-and-retry) instead of a client-side
  guess is simpler and just as correct. Removed the originally-planned `maxBatchBytes` config
  field since nothing would have read it.
- **2026-08-24 fix (user-directed, was originally flagged as a gap): MOB-09/10 anti-loop is
  now enforced by construction, not by integration discipline.** Originally, `IngestClient`
  had no delegate (proven), but excluding the ingest host from the app's own
  `instrumentedSession()` was a manual step nothing forced — a host app that forgot it would
  silently defeat the guarantee. User's call: "if an integrator has to remember a manual step
  or the SDK silently loops, that's a design defect." Fixed by introducing `IngestEndpoint`
  (`Sources/APMKit/IngestEndpoint.swift`) — one small value type (`url` + `appKey`) that is
  now the **single source of truth** both `APM.instrumentedSession()` and `IngestClient`
  consume:
  - `instrumentedSession()`'s `excludedHosts: Set<String> = []` parameter became a
    **required** `ingestEndpoint: IngestEndpoint`, plus an optional `additionalExcludedHosts`
    for anything beyond the ingest host. The function computes `ingestEndpoint.url.host` and
    unions it into the exclusion set internally — it is no longer possible to construct an
    instrumented session without the SDK itself knowing (and excluding) where uploads go.
  - `IngestClient.Configuration` was folded into the shared `IngestEndpoint` type (renamed
    `init(configuration:)` → `init(endpoint:)`) rather than kept as a separate,
    feat-005-only struct that could drift out of sync with whatever `instrumentedSession()`
    was told.
  - New test `ingestHostIsExcludedAutomatically`: a real request straight at the configured
    ingest host, through a real `instrumentedSession()`, with `additionalExcludedHosts`
    deliberately left empty — proves the exclusion holds with zero extra steps from the
    caller, not just that `excludedHosts` works when someone remembers to populate it (that
    was already covered by the renamed `additionalExcludedHostsAreNotCaptured`).
  - This is still not a full composition root (no `APM.start()` yet) — a host app still has
    to construct one `IngestEndpoint` and pass the *same instance* to both
    `instrumentedSession()` and `IngestClient`/`SyncEngine`. But two different values now have
    to be independently constructed with the *same URL* for the guarantee to fail, versus
    previously needing only one omission. Full one-call composition is still natural
    feat-006/010 territory (that's where `APM.start()`-style wiring belongs), but the
    per-feature safety guarantee itself no longer depends on it landing. User confirmed this
    scope split is correct: "the safety guarantee no longer depends on it, which was the
    concern."
  - Required updating 4 test files whose calls to `instrumentedSession()`/`IngestClient(...)`
    predated this change (`NetworkCaptureDelegateTests`, `PipelineEndToEndTests`,
    `SyncEngineTests`, `IngestClientTests`) — all now pass an explicit endpoint. `./verify.sh
    all` re-confirmed green (97/97) after the change, re-run 3× clean.
- **`EnvelopeFactory` keeps `SyncEngine` ignorant of how context is produced.** `userId`
  defaults to `nil` (feat-006 not landed), `integrity` defaults to `.unset` (feat-008 not
  landed) — both injectable closures, so those features only need to supply a value, not touch
  `SyncEngine` at all.
- **`MockHTTPServer` extended** (shared test infra, anticipated reuse per feat-003's own
  note) to capture request headers and the full body, looping additional `read()`s until
  `Content-Length` worth of body has arrived — the original single-`read()` implementation
  would have been unreliable for a real gzip-compressed envelope body. Kept backward
  compatible: existing feat-003 tests' 2-argument closures still work via a convenience `init`.

**Blockers** — none.

**Files added:** `Sources/APMKit/Sync/{CRC32,GzipEncoder,UploadOutcome,IngestUploading,
IngestClient,EnvelopeFactory,SyncEngine}.swift`, `Sources/APMKit/IngestEndpoint.swift`.
`Tests/APMKitTests/Sync/{CRC32Tests,GzipEncoderTests,EnvelopeFactoryTests,SyncEngineTests,
IngestClientTests}.swift`, `Tests/APMKitTests/Support/GunzipHelper.swift`.
**Files amended:** `Tests/APMKitTests/Support/MockHTTPServer.swift` (headers/body capture,
backward compatible); `Sources/APMKit/APMKit.swift` (`instrumentedSession()` now requires
`ingestEndpoint`, computes exclusion internally); `Sources/APMKit/Network/
NetworkCaptureDelegate.swift` (doc comment only); `Tests/APMKitTests/Network/
NetworkCaptureDelegateTests.swift`, `Tests/APMKitTests/PipelineEndToEndTests.swift` (updated
call sites + new anti-loop test).
