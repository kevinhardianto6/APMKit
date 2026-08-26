# feat-004 · Scrubbing

- **Status:** ✅ done · closed 2026-08-24 · **Depends on:** feat-003
- **Requirements:** last step before disk write. Header allowlist (Content-Type/Length,
  Accept, User-Agent only); redact query-param values; normalize id/UUID/long-number path
  segments; never capture bodies; pattern-redact (ID phone `08xx`/`+62xx`, email, JWT-like,
  ≥10-digit runs) over all strings incl. breadcrumbs and error text. SEC-01..05b.
- **Done when:** phone numbers removed from URLs/paths/errors/breadcrumbs (tests).

| ✓ | Check | By | Proof |
|:-:|-------|----|-------|
| ✅ | Phone number removed from a `network` event's `path` | Kevin Hardianto | `removesPhoneFromPath` (via `PathNormalizer` id-segment normalization) |
| ✅ | Phone number removed from error-like message text (feat-006 doesn't exist yet — proves the pipeline is generic) | Kevin Hardianto | `removesPhoneFromErrorMessage` |
| ✅ | Phone number removed from breadcrumb-like message text (feat-007 doesn't exist yet — same generic-pipeline proof) | Kevin Hardianto | `removesPhoneFromBreadcrumbMessage` |
| ✅ | Phone number removed from `ctx.screen` (docs/02 §6.1 `OTPVerification-0812xxxxxxx` example) | Kevin Hardianto | `removesPhoneFromScreenName` |
| ✅ | SEC-05: phone/email/JWT-like/≥10-digit patterns, each independently | Kevin Hardianto | `PatternRedactorTests` (8 tests) |
| ✅ | SEC-03b: UUID and long-digit path segments → `{id}`, word segments untouched | Kevin Hardianto | `PathNormalizerTests` (6 tests) |
| ✅ | SEC-02: header allowlist — wired live (see amendment below) | Kevin Hardianto | `HeaderAllowlistTests` (4 tests) + `PipelineEndToEndTests.piiNeverReachesDisk` |
| ✅ | SEC-03: query-param value redaction — wired live (see amendment below) | Kevin Hardianto | `QueryParameterScrubberTests` (4 tests) + `PipelineEndToEndTests.piiNeverReachesDisk` |
| ✅ | End-to-end: `Scrubber` in front of a real `FileDiskQueue` — raw phone number never touches disk bytes | Kevin Hardianto | `endToEndScrubbedBeforeDiskWrite` (reads the actual file content, not just the in-memory `Event`) |
| ✅ | Clean events pass through untouched (no false-positive redaction) | Kevin Hardianto | `leavesCleanEventUntouched` |
| ✅ | End-to-end via the REAL capture path: a genuine request with `?msisdn=...` and an `Authorization` header never lands on disk unredacted | Kevin Hardianto | `PipelineEndToEndTests.piiNeverReachesDisk` (real `NetworkCaptureDelegate` → `Scrubber` → `FileDiskQueue`, asserts on actual file bytes) |

29 tests total, `./verify.sh all` → `HARNESS_VERIFY: PASS (all)` (2026-08-24), re-run 3× clean.

**Review history:** user approved the original feat-004 implementation ("the disk-level
end-to-end test and the EventSink placement are exactly right"), then directed one follow-up
amendment (below) before final sign-off, rather than deferring it to a later feature.

**2026-08-24 amendment — SEC-02/03 wired live (user-directed).** Originally flagged as
implemented-but-dormant (see the struck-through reasoning kept below for history). User's
call: don't leave them dormant — add live capture as a small amendment to feat-003's
`NetworkCaptureDelegate`, keeping the layering strict:
- `NetworkCaptureDelegate` now captures the **raw, unredacted** query string (appended to
  `path` as `?query=string`) and **raw, unfiltered** request/response headers (as an additive
  `req_headers`/`res_headers` JSON-string attribute — docs/01 §4.1/§4.2 has no headers field,
  so this is additive per §11's change rules, not a breaking change).
- `Scrubber` is the **only** place any of it gets filtered: `QueryParameterScrubber` redacts
  query values (names kept) as part of the same `path`-scrubbing step that already did
  `PathNormalizer`; `HeaderAllowlist` filters `req_headers`/`res_headers` down to
  Content-Type/Content-Length/Accept/User-Agent.
- Deliberately did **not** pre-filter in the capture delegate — capture stays raw/dumb,
  `Scrubber` stays the single unbypassable enforcement point. This was an explicit design
  constraint from the user, not just convenient reuse of existing code.
- New `PipelineEndToEndTests.piiNeverReachesDisk` drives a real request (real `MockHTTPServer`,
  real `URLRequest` with `?msisdn=081234567890&page=2` and an `Authorization: Bearer
  super-secret-token-xyz` + `Cookie` header) through the full real pipeline and asserts on the
  **actual bytes written to the queue file** — not just the in-memory `Event` — that neither
  the phone number, the bearer token, nor the cookie value, nor the `Authorization`/`Cookie`
  header names themselves, ever appear on disk.
- `req_headers`/`res_headers` being a JSON-encoded string (not a structured field) is a
  pragmatic choice given `AttributeValue` only supports scalars — flagged as another docs/01
  gap (no headers field exists in the schema at all) the user may want to formalize the way
  `MOB-02b` formalized the http_error decision.

~~**SEC-02/03 implemented but not wired into any live capture path**~~ *(superseded by the
amendment above — kept for history)*: feat-003's `NetworkCaptureDelegate` originally never
captured headers or query strings at all, so `HeaderAllowlist`/`QueryParameterScrubber` had
nothing live to filter. Per `CONSTITUTION.md` (no drive-by edits to closed features), that gap
was surfaced as an explicit question rather than silently left or silently fixed by expanding
feat-004 into feat-003's territory without asking.

**Other decisions**
- **SEC-04 (never capture bodies) needs no code in this feature.** `docs/01` §4.1/§4.2 have no
  body field in the `network`/`network_failure` schema, so the requirement is satisfied
  structurally by the schema itself, not by anything `Scrubber` does.
- **Scrubbing is generic across event types, not network-specific.** `Scrubber.receive`
  applies blanket `PatternRedactor` to every string-valued attr regardless of `event.type`,
  plus `PathNormalizer` specifically for the `path` attr when present. Verified this works
  ahead of feat-006 (manual API/error) and feat-007 (breadcrumbs) actually existing, by
  constructing synthetic `error`/`breadcrumb`-typed events directly — satisfies SEC-05b's
  "works even for data developers send via manual API" requirement by construction, not by
  coincidence.
- **`DiskQueueEventSink` adapter added** (`Sources/APMKit/Storage/`) so `Scrubber` can sit in
  front of a real `FileDiskQueue` in tests and in the eventual composition root — `DiskQueue`
  itself still knows nothing about `EventSink`/capture vocabulary. Disk-write failures are
  swallowed (`try?`) per `CONSTITUTION.md` rule #1; proper failure counting is feat-010's
  self-health counters (MOB-27), not implemented yet.
- **Path-segment "long digit run" threshold is 5 digits** for `PathNormalizer` (docs only says
  "angka panjang" / long numbers, no threshold given) — judgment call, conservative middle
  ground. `PatternRedactor`'s separate ≥10-digit blanket rule still runs afterward on every
  attr including the already-normalized path, so there's a second layer regardless of this
  specific threshold choice.

**Blockers** — none.

**Files added:** `Sources/APMKit/Scrubbing/{PatternRedactor,PathNormalizer,HeaderAllowlist,
QueryParameterScrubber,Scrubber}.swift`, `Sources/APMKit/Storage/DiskQueueEventSink.swift`.
`Tests/APMKitTests/Scrubbing/{PatternRedactorTests,PathNormalizerTests,HeaderAllowlistTests,
QueryParameterScrubberTests,ScrubberTests}.swift`.
**Files amended (2026-08-24, SEC-02/03 wired):**
`Sources/APMKit/Network/NetworkCaptureDelegate.swift` (raw query+headers capture),
`Sources/APMKit/Scrubbing/Scrubber.swift` (query/header filtering wired in).
`Tests/APMKitTests/PipelineEndToEndTests.swift` (new, real-pipeline disk-level proof).
