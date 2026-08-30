# feat-011 · TLS Floor + Fail-Closed

- **Status:** ✅ done · closed 2026-08-29 · **Depends on:** feat-005 (`IngestClient`),
  feat-010 (`RemoteConfigFetcher`)
- **Requirements:**
  - **SEC-10 (P0):** TLS 1.2+ explicitly enforced by the SDK's own sessions, not inherited
    from the host app's ATS configuration.
  - **SEC-12 (P0):** fail closed on any TLS validation failure, for any reason — applies
    whether or not feat-015's (future) optional pinning is ever turned on.
- **Done when:** a real TLS failure against a real `IngestClient`/`RemoteConfigFetcher`
  connection leaves data on disk, never retries over anything weaker. **Met.**

## What was built

- `Sources/APMKit/Sync/SDKOwnedSessionConfiguration.swift` — one shared
  `URLSessionConfiguration` factory (`tlsMinimumSupportedProtocolVersion = .TLSv12`) used by
  both `IngestClient` and `RemoteConfigFetcher`'s default `session` parameter. Explicitly
  **not** used by `APM.instrumentedSession()` — that's the host app's own traffic, and this
  SDK has no business imposing a TLS floor on connections it doesn't originate.
- `IngestClient`/`RemoteConfigFetcher`'s default `init` now builds its session from
  `SDKOwnedSessionConfiguration.make()` instead of `.default` — the only production code
  change this feature needed.

## SEC-12 — confirmed by investigation, not rebuilt

Per the `FEATURES.md` scoping note before this feature started: read both `IngestClient` and
`RemoteConfigFetcher` (and `SyncEngine.handle(outcome:...)`, which is what acts on their
results) before writing anything. Confirmed: **no code path anywhere retries a failed request
over a weaker connection.** Every `UploadOutcome`/`nil`-config case either keeps data on disk
and backs off (transport failure, server error, rate limited, unauthorized) or drops the batch
outright (rejected) — none of them touch the URL scheme, the session, or fall back to reading
an unprotected response. This was already true before this feature started; the deliverable
here is the test that locks it in, not new production code. Saying so explicitly rather than
inventing fallback-prevention logic that wasn't needed — a proven existing guarantee is a
legitimate outcome of this feature, not a lesser one.

## Verification — real TLS-layer failure, not mocked

`MockHTTPServer` only ever speaks plain HTTP/1.1 (loopback raw sockets, no TLS support by
design — same test-infra philosophy as the rest of this repo, avoid third-party dependencies).
Rather than building actual self-signed-certificate TLS server infrastructure just for this
feature, both new tests (`IngestClientTests.realTLSLayerFailureFailsClosed`,
`RemoteConfigFetcherTests.realTLSLayerFailureFailsClosed`) point the client at `https://` on
the mock server's port. Since the server only speaks plain HTTP, the TLS handshake genuinely
fails — the server never sends a `ServerHello` — producing a real `URLSession`-reported
TLS-layer error, not a mocked trust-evaluation result. This doesn't test "a bad certificate is
rejected" specifically (that needs a real cert), but it does test SEC-12's actual wording —
"jika validasi TLS gagal karena sebab apa pun" (fails for any reason) — with a genuinely real
failure. Both tests assert the result is never success/a config (`!= .accepted` / `== nil`),
run 4× clean including 3 explicit repeats to rule out timing flakiness (~1.04s consistently,
matching the 1.0s `timeoutIntervalForRequest`).

Plus two direct configuration tests (`defaultSessionEnforcesTLS12Floor` on both types)
asserting `session.configuration.tlsMinimumSupportedProtocolVersion == .TLSv12` — a real
assertion against the actual production configuration object, not a stand-in.

**No host-vs-iOS gap here** — `URLSessionConfiguration.tlsMinimumSupportedProtocolVersion` and
TLS handshake behavior are identical on macOS and iOS; no Simulator-only verification needed
for this feature, unlike feat-008/009/010's OS-level probes.

182 tests (was 178 at feat-010 close; +4). `./verify.sh build`/`test` both `HARNESS_VERIFY:
PASS`, re-run 4× clean.

**Decisions** — none beyond what `FEATURES.md` already recorded when this feature was scoped
(the SEC-11 P1→P2 demotion, and this feature's own split-out from the old combined TLS+pinning
feature). **Blockers** — none.

**Files added:** `Sources/APMKit/Sync/SDKOwnedSessionConfiguration.swift`.
**Files amended:** `Sources/APMKit/Sync/IngestClient.swift`,
`Sources/APMKit/Stability/RemoteConfigFetcher.swift` (default session + doc comments),
`Tests/APMKitTests/Sync/IngestClientTests.swift`,
`Tests/APMKitTests/Stability/RemoteConfigTests.swift` (+2 tests each).
