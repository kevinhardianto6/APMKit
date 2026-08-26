# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Build the APM Kit iOS SDK (Phase 1 network observability + Phase 2 crash
  reporting), per docs/00-02.
- **Active feature:** none — feat-004 approved and closed (with a same-day amendment to wire
  SEC-02/03 live). Not yet started feat-005.
- **Status:** —
- **Last verify:** `./verify.sh all` → `HARNESS_VERIFY: PASS (all)`, 2026-08-24, 71 tests,
  re-run 3× clean.

## Next step

Ready to start feat-005 (Sync Engine, MOB-07/08/09) whenever asked: batched upload (≤200
events/≤1MB gzip) with the exact `01 §7` response-code contract (202/400/401/403/413/429/5xx),
using `MockHTTPServer` (already built) for the mock-server tests. Uploader must use a separate
non-instrumented `URLSession`, and the ingest host must be added to `excludedHosts` on the
capture session (MOB-10 anti-loop — the wiring point already exists in
`NetworkCaptureDelegate`/`APM.instrumentedSession`).

## Parked

- None.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `archive/features/feat-003.md` | Added | Rotated feat-003 detail on closing it |
| `archive/features/feat-004.md` | Added | Rotated feat-004 detail on closing it (incl. the SEC-02/03 amendment) |
| `archive/sessions/2026-08-24-feat-003.md` | Added | Rotated prior session's Changes table, incl. commit-message history rewrite |
| `Sources/APMKit/Scrubbing/*.swift` (5 files) | Added | feat-004: PatternRedactor, PathNormalizer, HeaderAllowlist, QueryParameterScrubber, Scrubber |
| `Sources/APMKit/Storage/DiskQueueEventSink.swift` | Added | Adapter so Scrubber can sit in front of a real FileDiskQueue |
| `Tests/APMKitTests/Scrubbing/*.swift` (5 files) | Added | 28 tests |
| `Sources/APMKit/Network/NetworkCaptureDelegate.swift` | Amended: raw query string + raw req/res headers captured | User-directed follow-up: wire SEC-02/03 live, capture stays raw, Scrubber stays sole filter |
| `Sources/APMKit/Scrubbing/Scrubber.swift` | Amended: filters query values + header allowlist | Same amendment |
| `Sources/APMKit/Scrubbing/{HeaderAllowlist,QueryParameterScrubber}.swift` | Doc comments updated ("not wired" → wired) | Reflect amendment |
| `Tests/APMKitTests/PipelineEndToEndTests.swift` | Added | Disk-level proof through the REAL capture pipeline (real request, real headers) |
| `FEATURES.md` | feat-003 ✅ archived (amendment noted); feat-004 ✅ archived | User approved feat-004 + amendment |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
