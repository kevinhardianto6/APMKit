# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Build the APM Kit iOS SDK (Phase 1 network observability + Phase 2 crash
  reporting), per docs/00-02.
- **Active feature:** feat-003 · Network Capture
- **Status:** 🟠 needs verification — implemented + tested, stopped per build-order rule to
  wait for review before starting feat-004 (Scrubbing).
- **Last verify:** `./verify.sh all` → `HARNESS_VERIFY: PASS (all)`, 2026-08-24 (42/42, after
  the docs/01 §4.2 alignment fix below).

## Next step

User hand-edited `docs/01-Kontrak-Data-API.md` (§4.2/§5, new `status_code` field + note) and
`docs/02-Mobile-SDK.md` (new requirement `MOB-02b`) to formally document the http_error
dual-event behavior — this matches what feat-003 already implemented. One code fix applied to
match exactly: `emitHTTPErrorEvent` no longer synthesizes placeholder `error_domain`/
`error_code` (docs now say those are required only for transport failures, not http_error).
Re-verified green. Still awaiting review of feat-003 overall. On approval: mark ✅, rotate to
`archive/features/feat-003.md`, then start feat-004 (Scrubbing, SEC-01..05b) — the last
mandatory gate before feat-002's DiskQueue receives real events, since Capture → Scrub → Disk
is enforced structurally via `EventSink` (feat-004 implements it in front of DiskQueue).

## Parked

- None.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `archive/features/feat-002.md` | Added | Rotated feat-002 detail on closing it |
| `archive/sessions/2026-08-24-feat-002.md` | Added | Rotated prior session's Changes table |
| `Sources/APMKit/Network/*.swift` (5 files) | Added | feat-003: FailureCategory(+Mapper), EventSink protocol, NetworkCaptureForwardingDelegate, NetworkCaptureDelegate |
| `Sources/APMKit/APMKit.swift` | Added `APM.instrumentedSession(...)` | feat-003 done-when requirement |
| `Package.swift` | Added `.macOS(.v11)` platform (non-distribution) | Host `swift build`/test needs iOS-15-era API availability (Network's tls_protocol_version_t) |
| `Tests/APMKitTests/Network/*.swift`, `Tests/APMKitTests/Support/{MockHTTPServer,CollectingEventSink}.swift` | Added | feat-003: 20 tests — real loopback requests, real timeout/cancel, pure failure-mapping, pinning-rejection distinction, MOB-10 exclusion |
| `FEATURES.md` | feat-002 → ✅ (archived); feat-003 → 🟠 needs verification | Evidence recorded, done-when met, http_error ambiguity resolved per user answer |
| `docs/01-Kontrak-Data-API.md`, `docs/02-Mobile-SDK.md` | User edited directly (§4.2 status_code, MOB-02b) | Formalizes the http_error decision already implemented in feat-003 |
| `Sources/APMKit/Network/NetworkCaptureDelegate.swift` | `emitHTTPErrorEvent` no longer synthesizes `error_domain`/`error_code` | Match the now-official §4.2 table exactly |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
