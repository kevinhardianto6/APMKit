# Phase 1 wrap-up — APM Kit iOS SDK

2026-08-28. feat-001..008 all ✅. This is the requirement-by-requirement accounting behind
that — not just "8 features shipped," but which MOB-/SEC- IDs are actually covered, which
are genuinely deferred (and why), and what still needs a real device/simulator before the
pilot ships.

## Covered

### Network observability (docs/02 §3.1)
- **MOB-01, MOB-02, MOB-02b, MOB-03, MOB-10** — feat-003 (+feat-005 for the MOB-10/MOB-09
  auto-exclusion fix). Full request metrics, failure_category mapping, http_error dual-event
  behavior, pinning-vs-cancel distinction, anti-loop enforced by construction via
  `IngestEndpoint`.

### Local storage (docs/02 §3.2)
- **MOB-04, MOB-05, MOB-06, MOB-14** — feat-002, feat-004. Atomic write, crash/restart
  survival, FIFO eviction at cap, scrubbing runs before every disk write.

### Delivery (docs/02 §3.3)
- **MOB-07, MOB-08, MOB-09** — feat-005 (+feat-007 for the connectivity/background triggers).
  Full `01 §7` response contract, three required triggers, delete-only-after-2xx.

### Developer API (docs/02 §3.4)
- **MOB-11, MOB-12, MOB-13, MOB-28** — feat-006, feat-007. `setUser`/`logError`/`breadcrumb`,
  ring buffer attached to errors, lifecycle/connectivity genuinely automatic, screen tracking
  host-invoked by design (no swizzling — user-approved deviation from a literal "automatic"
  reading, now reflected in docs/02 MOB-12 itself).

### Device integrity (docs/02 §3.8)
- **MOB-29, MOB-30, MOB-31** — feat-008. All four `integrity` fields wired, `is_dev_mode`/
  `debugger_attached` as confirmed-independent booleans, cached once per session.

### Client-side security (docs/02 §6)
- **SEC-01, SEC-02, SEC-03, SEC-03b, SEC-04, SEC-05, SEC-05b, SEC-06, SEC-07** — feat-002,
  feat-004 (+ its SEC-02/03 live-wiring amendment), feat-006. Scrubbing is the sole
  enforcement point for headers/query values/path normalization/pattern redaction; proven on
  real disk bytes three separate times (feat-004's PII test, feat-006's `user_id` leak test,
  feat-007's breadcrumb leak test) — not just asserted once and assumed to generalize.
  SEC-04 is satisfied structurally (no body field exists in the schema at all, so there's
  nothing to accidentally capture). SEC-07's file protection is implemented but not
  independently verifiable on the macOS test host — see manual-verification list below.

## Deferred — by design (explicitly out of scope for this epic)

These aren't gaps; they're scope boundaries the epic was given at the start:

- **MOB-25** (sample app + integration docs) — docs/00 §7 puts this in Phase 3, and the
  original build order explicitly excluded it.
- **SEC-19, SEC-21, SEC-22** (release process, data inventory doc, privacy-label
  consequences) — process/documentation items for the backend/ops side and Phase 3, not SDK
  code.
- **BE-21 backend verification** (that raw `user_id` is actually discarded after hashing) —
  can't be verified without a backend, which doesn't exist yet. The SDK-side half (raw value
  never persisted, never leaks elsewhere) is proven; the backend half is out of this epic's
  reach entirely.
- **Phase 2/3 items not yet due**: MOB-15..22, MOB-27 (feat-009/010), SEC-09 (crash report
  encryption trade-off, feat-009-scoped), SEC-20 (remote config code-execution constraint,
  feat-010-scoped).

## Deferred — real gaps, not yet flagged as their own feature rows

These are P0/P1 requirements from docs/02 that don't fall under Phase 2/3 and aren't
explicitly satisfied by any feat-001..008 work. None were assigned an F-number in the
original build order (same category of gap as SEC-07 and SEC-02/03 turned out to be —
surfaced only by actually cross-checking the requirement list against what got built, not
because anyone flagged them during planning):

- **Performance budget (docs/02 §5) is not measured anywhere.** Binary size (≤1.5MB), cold
  start overhead (≤30ms p95), CPU (≤2%), memory (≤8MB), disk (≤20MB, though MOB-06's cap
  enforces this one specifically) — docs/02 §5 says this must be "measured automatically in
  CI, not checked manually," and a violation means "cannot ship." Nothing in this repo
  measures any of it. This is the single largest gap relative to how strongly the spec words
  it.
- **SEC-08** (AES-GCM encryption at rest, P1) — the disk queue is protected by
  `FileProtectionType` (SEC-07) but not separately encrypted. P1, not P0, but genuinely
  unimplemented.
- **SEC-10** (TLS 1.2+ enforced, cleartext disabled) — likely satisfied by default `URLSession`
  behavior and platform ATS, but nothing in `IngestClient`/`NetworkCaptureDelegate` explicitly
  sets `minimumTLSVersion` or otherwise *enforces* it at the SDK level; it's an assumption
  resting on OS defaults, not a verified guarantee.
- **SEC-11, SEC-12, SEC-14** (certificate pinning *on the SDK's own ingest connection*, fail-
  closed behavior, key rotation via remote config) — not implemented. Worth being precise
  about what feat-003 actually built: `NetworkCaptureForwardingDelegate` lets a *host app*
  plug in pinning for traffic the SDK *observes*; it says nothing about the SDK's *own*
  connection to its ingest endpoint, which SEC-11 is actually about. That connection is
  currently unpinned.
- **MOB-23/24** (CocoaPods distribution, semver/compatibility documentation) — only SPM
  packaging exists; no `.podspec`, no versioning/changelog process set up yet.
- **MOB-26** (P1 debug-mode local logging) — not implemented, not previously flagged.

None of these block Phase 2 from starting (feat-009 depends on feat-001..008, not on these),
but they're real and should become their own `FEATURES.md` rows before this SDK is considered
pilot-ready, not just before v1.

## Manual device/simulator verification list (running, for the pilot)

Everything below compiles and its *logic* is unit-tested on the macOS host toolchain, but the
real OS-level behavior cannot be exercised by `swift test` and needs an actual device or
iOS Simulator run:

1. **feat-008's iOS-gated integrity probes** — `isRooted()`'s real file/symlink/sandbox-write
   checks, `isDevMode()`'s provisioning-profile/receipt lookup, and `isEmulator()`'s `true`
   branch (only reachable when actually compiled for Simulator). Only the pure
   `JailbreakVerdict`/`DevModeVerdict` combination logic is proven by `swift test`.
2. **feat-007's OS-level automatic breadcrumb firing** — real `UIApplication` lifecycle
   notifications and real `NWPathMonitor` connectivity transitions actually invoking
   `AutomaticBreadcrumbSource`'s `recordLifecycle`/`recordConnectivity`. Only the mapping
   logic those methods contain is proven by `swift test`.
3. **SEC-07's `FileProtectionType`** (feat-002) — the protection level and backup-exclusion
   flag have no observable effect on the macOS test host; needs a real-device/simulator file
   attribute check.
4. **docs/02 §7's explicit Fase 1 test scenarios** not yet covered by any automated test:
   disk full (real `ENOSPC`, not just the SDK's own size cap), and force-quit specifically
   *during* an in-flight upload (offline buffering itself is tested; the exact "killed
   mid-HTTP-request" timing is not).
5. **Performance budget** (see gap above) — needs to be measured on a real device at all,
   automated or not.

## Test suite size at close of Phase 1

131 tests, `./verify.sh all` → `HARNESS_VERIFY: PASS (all)`, re-run 3× clean at every feature
boundary through feat-008.
