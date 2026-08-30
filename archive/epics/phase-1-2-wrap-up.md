# Phase 1 + 2 wrap-up — APM Kit iOS SDK

2026-08-29. All 10 features (feat-001..010) ✅ — the epic is complete. Phase 1 detail lives in
`archive/epics/phase-1-wrap-up.md`; this file is the full-epic view: every MOB-/SEC- ID's
status in one table, what Phase 3 explicitly excludes, the manual verification checklist as it
stands today, and what an Android port would need for parity with what this iOS SDK actually
does (not just what the spec says both platforms must do).

## Full requirement coverage

**MOB- (Mobile SDK requirements, docs/02)**

| ID | Requirement | Status | Feature |
|---|---|---|---|
| MOB-01/02/02b/03 | Network capture: full request metrics, failure_category mapping | ✅ | feat-003 |
| MOB-04/05/06 | Disk queue: atomic write, crash/restart survival, FIFO eviction at cap | ✅ | feat-002 |
| MOB-07/08/09 | Sync: `01 §7` response contract, 3 required triggers, delete-only-after-2xx | ✅ | feat-005 |
| MOB-10 | Anti-loop: SDK's own upload traffic never self-captured | ✅ | feat-003 + feat-005 |
| MOB-11 | `logError`/`breadcrumb` public API | ✅ | feat-006, feat-007 |
| MOB-12 | Automatic lifecycle/connectivity breadcrumbs; host-invoked screen tracking (no swizzle) | ✅ | feat-007 |
| MOB-13 | Breadcrumb ring buffer (100), attached to every crash/error | ✅ | feat-007 |
| MOB-14 | Scrubbing runs before every disk write | ✅ | feat-004 |
| MOB-15/16/17 | Crash/signal capture, minimal on-disk report, `binary_images`+UUID | ✅ | feat-009 |
| MOB-18 | Hang detection >2s | ✅ | feat-010 |
| MOB-19 | Cold-start metric | ✅ | feat-010 |
| MOB-20/21 | Remote config fetch (cached fallback) + kill switch | ✅ | feat-010 |
| MOB-22 | Sampling per event type, remote-config-controlled | 🟡 not started | not filed — see Deferred |
| MOB-23 | Distribution: SPM done; **CocoaPods not done** | 🟡 partial | not filed — see Deferred |
| MOB-24 | Semver + compatibility doc | 🟡 not started | not filed — see Deferred |
| MOB-25 | Sample app + integration docs | 🟡 not started | **Phase 3, by design** |
| MOB-26 | Debug-mode local logging | 🟡 not started | not filed — see Deferred |
| MOB-27 | Self-health counters (written/sent/dropped) | ✅ | feat-010 |
| MOB-28 | `setUser(id)` + stable random fallback | ✅ | feat-006 |
| MOB-29/30/31 | Device integrity: emulator/root/dev-mode/debugger flags | ✅ | feat-008 |

**SEC- (client-side security, docs/02 §6)**

| ID | Requirement | Status | Feature |
|---|---|---|---|
| SEC-01 | Scrub before disk write | ✅ | feat-004 |
| SEC-02 | Header allowlist | ✅ | feat-004 |
| SEC-03/03b | Query redaction, path normalization | ✅ | feat-004 |
| SEC-04 | No request/response body capture | ✅ (structural — no body field in schema) | feat-001 |
| SEC-05/05b | Pattern redaction, last-layer enforcement | ✅ | feat-004 |
| SEC-06 | `user_id` raw client-side, never leaks elsewhere | ✅ | feat-006 |
| SEC-07 | `FileProtectionType` + backup exclusion | ✅ (real-device verification still pending — checklist #3) | feat-002 |
| SEC-08 | AES-GCM at-rest encryption, P1 | 🟡 not started | not filed — see Deferred |
| SEC-09 | Crash report exception from encryption-at-write | ✅ (documented trade-off, verified end-to-end) | feat-009 |
| SEC-10 | TLS 1.2+ enforced, cleartext disabled | 🟡 assumed (OS/ATS default), not explicitly enforced by the SDK | not filed — see Deferred |
| SEC-11/12 | Certificate pinning on the SDK's *own* ingest connection, fail-closed | 🟡 not started | not filed — see Deferred |
| SEC-13 | App key treated as identifier, not credential | ✅ (by design — `IngestEndpoint.appKey`, no validation/secrecy logic anywhere) | feat-001/005 |
| SEC-14 | Key rotation via remote config | 🟡 not started (fetch mechanism exists via feat-010, nothing reads a key field yet) | not filed — see Deferred |
| SEC-19 | Release process (checksums, pinned deps) | — process/ops, not SDK code | **Phase 3 / out of epic** |
| SEC-20 | Remote config: predefined flags only, no dynamic execution | ✅ (structural — `RemoteConfig` is a fixed `Codable` shape) | feat-010 |
| SEC-21/22 | Data inventory doc, privacy-label consequences | — process/documentation | **Phase 3 / out of epic** |
| SEC-24, SEC-28 | Leak audit, server-side key handling | — Backend-owned, not this SDK's scope | out of epic |

## Deferred to Phase 3 (by design — not gaps)

Per docs/00 §7 and the epic's own scope line, these were never in this epic's build order:
- **MOB-25** — sample app + integration docs
- **SEC-19, SEC-21, SEC-22** — release process, data inventory, privacy-label consequences
- Backend/dashboard/symbolication service, MOB-22's sampling *infrastructure* on the backend
  side, BE-21 backend verification (raw `user_id` actually discarded post-hash) — none of this
  is SDK code and none of it exists yet to verify against.

## Real gaps — not Phase 3, just not built (carried forward + updated)

Everything from `phase-1-wrap-up.md`'s equivalent section, re-checked against what feat-009/
010 actually touched:

- **Performance budget (docs/02 §5) — still not measured anywhere.** Binary size, cold-start
  overhead, CPU, memory, disk. feat-010 built the cold-start *metric* (MOB-19) but that's the
  SDK reporting a number, not CI enforcing the ≤30ms p95 *budget* on the SDK's own overhead —
  different things. Still the single largest gap relative to how strongly the spec words it
  ("Diukur otomatis di CI... Dilanggar = tidak boleh rilis").
- **SEC-08** (AES-GCM at rest) — still unimplemented. Notably, feat-009's SEC-09 trade-off
  explicitly assumes SEC-08 exists ("dienkripsi saat peluncuran aplikasi berikutnya") — the
  next-launch crash-report processing pipeline (`CrashReportProcessor`) does NOT currently
  perform any encryption step; it maps and forwards through the same disk queue as everything
  else, which is exactly as protected (SEC-07 only) as any other event. This is worth a closer
  look before pilot: the spec's stated mitigation for the raw-crash-report PII window assumes
  a control that doesn't exist yet.
- **SEC-10** — still an assumption resting on OS/ATS defaults, not an explicit SDK-level
  enforcement.
- **SEC-11, SEC-12, SEC-14** — the SDK's own connection to its ingest/config endpoints is
  still unpinned; feat-010's remote config fetch (`RemoteConfigFetcher`) uses the identical
  bare-`URLSession` pattern as `IngestClient` and inherits the same gap. Key rotation (SEC-14)
  has no consumer yet even though the fetch mechanism could carry a key field.
- **MOB-22** — `RemoteConfig.sampling` is now parsed and cached (feat-010) but not enforced
  anywhere; no event type currently samples.
- **MOB-23/24** — still SPM-only; no CocoaPods podspec, no semver/changelog process.
- **MOB-26** — debug-mode local logging still not implemented.

None of these blocked Phase 2 (feat-009/010 didn't depend on any of them) and none block the
epic being "done" against its own stated scope — but they're real, and several (SEC-08/10/11/
12, performance budget) are P0/P1 items the spec treats as release-blocking, not nice-to-haves.
Worth their own `FEATURES.md` rows before a real pilot rollout to other teams, not just before
a hypothetical v2.

## Manual verification checklist — current state

Full list lives in `FEATURES.md` → "Manual verification checklist (pilot)" (single source,
not duplicated here). As of 2026-08-29:

| # | Item | Status |
|---|---|---|
| 1 | Integrity probes real detection (feat-008) | ☐ not verified |
| 2 | OS-level automatic breadcrumb firing (feat-007) | ☐ not verified |
| 3 | SEC-07 `FileProtectionType` real effect (feat-002) | ☐ not verified |
| 4 | Disk-full / force-quit-mid-upload scenarios (feat-002/005) | ☐ not verified |
| 5 | Performance budget, measured on a real device (Phase 1 all) | ☐ not verified |
| 6 | Real crash captured by KSCrash on iOS Simulator (feat-009) | ☑ verified 2026-08-28 |
| 7 | Real >2s main-thread hang detected live (feat-010) | ☑ verified 2026-08-29 |

**2 of 7 verified.** Both verified items are Phase 2's own additions, verified in the same
session they were built, via a permanent, re-runnable `xcodebuild test`-based Simulator
harness (`IOSCrashHarnessTests`). Items 1–5 (all Phase 1) remain exactly as they were at
Phase 1's close — nothing in Phase 2 touched them, and no session since has picked them up.
This is the concrete punch list before a pilot rollout, not a hypothetical one.

## What an Android port would need for parity

docs/02 is written iOS-*and*-Android from the start ("§0: Berlaku untuk kedua platform kecuali
ditandai khusus... schema, kategorisasi, kontrak response wajib identik"), so parity is a
spec requirement, not a nice-to-have. What follows is specific to what THIS iOS
implementation actually built, cross-referenced against the doc's own Android call-outs —
not a generic "port to Android" essay.

**Wire-identical, no platform work beyond re-implementing (docs/02 §0):**
`failure_category` enum, event schemas (§4), the `01 §7` response contract, fingerprinting
rules — all Android needs here is a faithful re-implementation against the same schema types,
with cross-platform contract tests (docs/00 M2's own stated done-criterion:
"Android mengirim payload yang identik dengan iOS untuk kasus uji yang sama" — not yet
possible to check since no Android SDK exists).

**Deliberately divergent — Android's version should be *more* automatic, not equivalent:**
- **Screen tracking (MOB-12).** iOS is host-invoked (`recordScreen(_:)`, no swizzling) because
  the only automatic mechanism — swizzling `viewDidAppear` — was explicitly rejected (risk of
  crash/UB, collision with other SDKs already swizzling it in this org's apps). Android has
  `ActivityLifecycleCallbacks`, an official, safe, non-swizzling hook — the doc is explicit
  that Android's version should be **genuinely automatic** here, and that only the *output*
  (a `breadcrumb` event, `category: navigation`) needs to match, not the trigger mechanism.
  Porting iOS's host-invoked pattern to Android would be *under*-delivering, not parity.
- **Network capture.** iOS wraps `URLSessionTaskDelegate` (feat-003). docs/02 §3.1 explicitly
  calls out that Android must use OkHttp's `EventListener`, not just `Interceptor` — only
  `EventListener` exposes `secureConnectStart`/`secureConnectEnd`/`callFailed`, which is what
  makes distinguishing `ssl_pinning_rejected` from a plain cancel (the same subtlety this iOS
  SDK's `NetworkCaptureDelegate` handles via trust-evaluation-stage tracking) possible on
  Android at all.
- **Crash reporting (MOB-15/16/17, this SDK's feat-009).** iOS wraps KSCrash — a mature,
  Darwin-specific signal/mach-exception library. Android has no direct KSCrash equivalent;
  the same "wrap a mature library, don't hand-roll" principle (`CONSTITUTION.md`/docs/00 §11
  decision 4) applies, but the actual library choice is an open decision for whoever builds
  the Android SDK — Android's crash-capture primitives (`Thread.UncaughtExceptionHandler`,
  native `SIGSEGV`/tombstone equivalents) are different enough from Darwin's mach exception
  ports that this isn't a straight port, it's an equivalent-shaped but separately-chosen
  dependency.
- **Hang detection (MOB-18).** iOS wraps KSCrash's `Watchdog` monitor (main-thread
  `CFRunLoopObserver` + a dedicated watchdog thread). Android's equivalent signal is ANR
  (Application Not Responding) detection — a different OS-level mechanism entirely (Android's
  own ANR dialog/watchdog, or `Looper`-based main-thread monitoring). The *output* (a
  `crash`/`crash_type: hang` vs `crash_type: anr` event, per docs/01 §4.3's enum which already
  has both values) needs to match; the mechanism can't be shared code at all.
- **Device integrity (MOB-29/30/31).** Every single heuristic is platform-specific by
  necessity — iOS checks Cydia/Sileo paths and sandbox-write tests; Android checks `su`
  binaries, Magisk/SuperSU packages, `test-keys` build tags, writable system partitions. The
  doc gives the exact Android-side checks already (§3.8), so this is direct reference, not
  design work — but it's 100% new platform-specific code, zero shared logic with
  `DeviceIntegrityDetector`.
- **Data-at-rest protection (SEC-07/08).** iOS uses `FileProtectionType` + Keychain (for a
  future SEC-08); Android uses internal storage + auto-backup exclusion + Android Keystore.
  Named explicitly as platform-parallel, not shared, in the spec itself.

**What ports cleanly as *design*, not code:** the write-local-first architecture (Capture →
Scrub → Disk → Sync), the anti-loop guarantee shape (exclude the SDK's own ingest host from
capture — same idea, different HTTP-client API to hook), the kill-switch/self-health-counter
architecture (feat-010 — `KillSwitch` wrapping the capture pipeline, counters at every
write/drop/send decision point), and the scrub-as-last-layer principle. None of this is
Swift-specific; all of it is a direct blueprint for the Android SDK's own architecture,
independent of which Kotlin/Java APIs end up implementing each piece.

**Bottom line:** an Android port is not a recompile-equivalent effort. The wire contract
(schemas, response codes, fingerprinting) is genuinely shared and should be built once and
referenced by both platforms' contract tests. Every OS-level integration point this SDK
implements — network capture, crash/hang detection, integrity heuristics, at-rest protection —
needs its own platform-native mechanism, chosen with the same "wrap mature libraries, avoid
undefined-behavior-risk hooks like swizzling" discipline this iOS SDK used throughout, not a
port of the Swift implementation.

## Test suite size at close of Phase 1 + 2

178 tests, `./verify.sh build`/`./verify.sh test` → both `HARNESS_VERIFY: PASS`, plus 3 real
iOS Simulator checks outside that count (`IOSCrashHarnessTests` phase 1/2/3, `xcodebuild test`,
not part of the default `swift test` run).
