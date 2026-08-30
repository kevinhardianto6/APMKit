# Features

> Scope backbone, grouped by epic (one epic = one PRD = one ID prefix).
> Status: 🟡 not started · 🔵 in progress · ✅ done · 🔴 blocked · 🟠 needs verification
> **One feature is active at a time per person** (see `state/<name>.md`) — the backlog may span epics.
> `By` = who actually did the work, from `git config user.name` on the machine that ran it.
> Completed feature detail → `archive/features/`. Completed *epics* → `archive/epics/`, listed under Shipped.

| Epic | Progress | Active / open |
|------|:--------:|---------------|
| Pre-Pilot Hardening | 0/5 | feat-011 |

---

## Epic · Pre-Pilot Hardening

**PRD:** `docs/02-Mobile-SDK.md` §5–6 (performance budget, client-side security) — no separate
PRD document; this epic remediates P0/P1/P2 requirements from the existing spec that the
shipped APM Kit iOS SDK epic left unfiled, surfaced by that epic's own wrap-up
(`archive/epics/phase-1-2-wrap-up.md` → "Real gaps"). **Prefix:** `feat-` (continues the same
sequence — one SDK, one PRD family, no reason to fork numbering for a remediation pass).
**Scope:** SEC-10/11/12 (TLS floor, fail-closed, optional pinning), the docs/02 §5 performance
budget, MOB-23/24 (distribution), SEC-08 (at-rest encryption). Explicitly **not** in scope:
Android (blocked on this epic per the user's own sequencing — parity notes are ready in the
wrap-up above, Android work starts after), MOB-22 (sampling), SEC-14 (key rotation), MOB-26
(debug logging) — those remain unfiled gaps, not silently rolled into this epic.
**Started:** 2026-08-29 · **Started by:** Kevin Hardianto

> **2026-08-29 re-scope:** SEC-11 (cert pinning on the SDK's own ingest connection) demoted
> P1 → **P2, opt-in, off by default** — a dated decision now recorded in `docs/02-Mobile-SDK.md`
> §6.3 itself (see the box under SEC-10/11/12). Short version: a cert rotation with pinning
> mandatory-on would silently kill telemetry across every installed app and take an app
> release to recover, while the threat it closes only matters once an attacker can already
> plant a CA on the device — at which point telemetry interception is not the org's biggest
> problem. This project started from an incident where a pinning failure blinded the team;
> shipping a monitoring SDK that can blind itself the same way, by default, was rejected.
> SEC-10 (TLS 1.2+ enforced) and SEC-12 (fail closed on *any* TLS validation failure,
> regardless of whether SEC-11 pinning is ever turned on) remain P0, non-negotiable, and are
> now split into their own small feature (feat-011) instead of being bundled with pinning.

Ordering is deliberate, per the user's own reasoning, not just numeric — TLS floor +
fail-closed first because it's small and P0; performance budget second because "violated =
don't ship" per spec wording; distribution third because it blocks other teams adopting the
SDK at all; at-rest encryption fourth because it can trail; optional pinning last because it's
now P2 and opt-in, the lowest-urgency item in the epic. Build order is otherwise the same
mandatory rule as before (`CONSTITUTION.md` → Prohibitions — process): one feature active at a
time, stop for review after each.

| ID | Feature | Status | By | Depends on | Requirements | Evidence |
|----|---------|:------:|----|------------|--------------|----------|
| feat-011 | TLS Floor + Fail-Closed | 🟡 | — | feat-005, feat-010 | SEC-10, SEC-12 | — |
| feat-012 | Performance Budget (CI-enforced) | 🟡 | — | feat-001..010 | docs/02 §5 | — |
| feat-013 | Distribution (CocoaPods + semver) | 🟡 | — | feat-001..010 | MOB-23/24 | — |
| feat-014 | At-Rest Queue Encryption | 🟡 | — | feat-002 | SEC-08 | — |
| feat-015 | Optional Certificate Pinning (opt-in, P2) | 🟡 | — | feat-011, feat-010 | SEC-11 | — |

### feat-011 · TLS Floor + Fail-Closed

- **Status:** 🟡 not started · **Depends on:** feat-005 (Sync Engine / `IngestClient`),
  feat-010 (`RemoteConfigFetcher` — the other SDK-owned connection this applies to)
- **Requirements:**
  - **SEC-10 (P0):** TLS 1.2+ explicitly enforced by the SDK's own sessions — set
    `tlsMinimumSupportedProtocolVersion` explicitly on both `IngestClient`'s and
    `RemoteConfigFetcher`'s `URLSessionConfiguration`, rather than inheriting whatever the
    host app's ATS settings happen to allow. A host app can weaken ATS globally for some
    unrelated legacy API; the SDK's own upload/config traffic has no reason to inherit that
    weakening — this matters specifically because this SDK ships into apps it doesn't control.
  - **SEC-12 (P0):** fail closed on **any** TLS validation failure, for **any** reason —
    applies whether or not feat-015's optional pinning is ever turned on. Data stays queued on
    disk; the SDK never falls back to an unprotected connection.
- **Note on scope — confirm, don't assume, before writing code:** neither `IngestClient` nor
  `RemoteConfigFetcher` currently has any code path that retries a failed request over a
  weaker/unprotected connection — every failure outcome (`.transportFailure`, `.serverError`,
  etc.) just backs off and retries the *same* request against the *same* session/URL
  (`SyncEngine.handle(outcome:...)`). If that holds up under actual investigation, **SEC-12's
  deliverable here is a test that locks the existing guarantee in, not new production code** —
  proving an already-true guarantee is a legitimate outcome, not a lesser one. Don't invent
  fallback-prevention logic that isn't needed just to have something to build.
- **Done when:** a real TLS failure (invalid/untrusted cert, a server forced below TLS 1.2)
  against a real `IngestClient`/`RemoteConfigFetcher` connection leaves the batch/config fetch
  failed and the data on disk — never a retry over anything weaker. Real handshake, not a
  mocked trust-evaluation result, same standard as feat-009/010's crash/hang verification.

### feat-012 · Performance Budget (CI-enforced)

- **Status:** 🟡 not started · **Depends on:** feat-001..010 (measures the whole SDK as it
  exists today)
- **Requirements:** docs/02 §5 — binary size ≤1.5MB compressed, cold-start overhead ≤30ms p95
  (the SDK's own added overhead, distinct from MOB-19's cold-start *metric* the SDK reports
  for the host app — feat-010 built the latter, not this), CPU ≤2% average, memory ≤8MB
  resident, disk ≤20MB (MOB-06 already enforces this one specifically at the code level;
  this feature is about *measuring and gating* it, not implementing the cap), zero main-thread
  blocking I/O. Spec wording is explicit: "Diukur otomatis di CI, bukan diperiksa manual...
  Dilanggar = tidak boleh rilis."
- **Open question for whoever picks this up:** this repo has no CI pipeline at all yet (no
  `.github/workflows/`, no equivalent) — confirm with the user whether this feature also sets
  one up, or only builds the measurement tooling a future CI would call. Don't assume either
  way; the spec only mandates the *enforcement*, not a specific CI provider.
- **Done when:** a runnable script/target measures binary-size delta and flags any main-thread
  I/O in the SDK's own code paths, with a documented pass/fail threshold matching docs/02 §5 —
  not just a report a human reads.

### feat-013 · Distribution (CocoaPods + semver)

- **Status:** 🟡 not started · **Depends on:** feat-001..010 (packages the whole SDK as it
  exists today)
- **Requirements:** MOB-23 — CocoaPods distribution alongside the existing SPM support (no
  change to SPM itself). MOB-24 — semver policy, a compatibility/changelog document, and the
  rule that breaking changes only land at a major version.
- **Done when:** a generated podspec passes `pod spec lint` (or equivalent local validation —
  no CocoaPods trunk push implied by "done" here, that's a release-process concern); a
  versioning document exists stating the policy and the SDK's current version number.

### feat-014 · At-Rest Queue Encryption

- **Status:** 🟡 not started · **Depends on:** feat-002 (`FileDiskQueue` — what gets encrypted)
- **Requirements:** SEC-08 — AES-GCM encryption of the on-disk event queue, key in Keychain
  (not `UserDefaults` — nothing in this SDK uses Keychain yet; this is the first feature that
  will). Must stay defensive per `CONSTITUTION.md` rule #1: a Keychain access failure must
  never throw into the host app.
- **Notable side effect, not a separate task:** feat-009's SEC-09 decision explicitly assumed
  this control exists ("crash report... dienkripsi saat peluncuran aplikasi berikutnya") and
  it didn't, until now. `CrashReportProcessor` already routes crash reports through the same
  `sink`/disk-queue pipeline as every other event (feat-009's own design) — so encrypting the
  queue here closes that assumption retroactively, without CrashReportProcessor itself needing
  any change. Worth confirming this explicitly when the feature closes, not just assuming it.
- **Done when:** on-disk queue files are not readable as plaintext (direct file inspection
  shows ciphertext, not JSON); a Keychain round-trip (write key, kill process, re-read key,
  decrypt existing queue) is verified on a real iOS Simulator — Keychain isn't meaningfully
  testable on the macOS host toolchain the same way `sysctl`-based checks are, so this likely
  needs the same `IOSCrashHarnessTests`-style real-Simulator harness feat-009/010 built.

### feat-015 · Optional Certificate Pinning (opt-in, P2)

- **Status:** 🟡 not started · **Depends on:** feat-011 (builds on the plain TLS floor),
  feat-010 (`RemoteConfigStore` — the kill switch)
- **Requirements (SEC-11, P2, per the 2026-08-29 docs/02 §6.3 decision):**
  - **Off by default.** Enabling pinning is a **per-app integration choice made at SDK setup**
    (a config value the host app passes in deliberately) — **not** a remote-config value.
    Remote config is only for the kill switch *after* pinning has already been enabled by the
    host, never for turning it on in the first place.
  - **Backup pin + kill switch are mandatory together whenever pinning is enabled** — not
    optional add-ons, not separable. Kill switch reuses `RemoteConfig.disabledFeatures`
    (e.g. `["cert_pinning"]`) — feat-010's existing, currently-inert field — rather than a new
    dedicated wire flag.
  - **"Stop pinning" ≠ "stop verifying."** When the kill switch disables pinning, the
    connection falls back to feat-011's plain TLS floor, **not** to an unverified connection —
    SEC-12's fail-closed guarantee applies identically whether pinning is on, off by default,
    or switched off remotely mid-flight. There is no state in which the SDK's own connection
    is unverified.
- **Done when:** pinning OFF (default) behaves identically to feat-011 alone — zero pinning
  code path active. Pinning ON rejects a real wrong-certificate handshake and fails closed. A
  simulated certificate rotation continues working via the backup pin without any switch flip.
  Flipping the `disabledFeatures` kill switch off disables pinning specifically (connection
  drops to the TLS floor, still verified) and back on re-enables it — proven the same way
  feat-010 proved the master kill switch: one test, real pipeline/session types, not fakes.

**Decisions** — none yet (nothing implemented). **Blockers** — none.

---

## Manual verification checklist (pilot)

Everything below compiles and its *logic* is unit-tested on the macOS host toolchain
(`swift test`), but the real OS-level/device behavior can't be exercised that way and needs an
actual iOS Simulator or device run. This is the running pre-ship checklist for the pilot app —
update rows in place as items get verified (or newly found); don't scatter new ones into
per-feature notes or archive files. Originally split across `archive/epics/phase-1-wrap-up.md`
and feat-009's Blockers; consolidated here 2026-08-28 so it's one list, not several.

| # | Item | From | Status |
|---|------|------|--------|
| 1 | Integrity probes: `isRooted()`'s real file/symlink/sandbox-write checks, `isDevMode()`'s provisioning-profile/receipt lookup, `isEmulator()`'s `true` branch (only reachable compiled for Simulator). Only the pure `JailbreakVerdict`/`DevModeVerdict` combination logic is proven by `swift test`. | feat-008 | ☐ not verified |
| 2 | OS-level automatic breadcrumb firing: real `UIApplication` lifecycle notifications and real `NWPathMonitor` connectivity transitions actually invoking `AutomaticBreadcrumbSource`'s `recordLifecycle`/`recordConnectivity`. Only the mapping logic is proven by `swift test`. | feat-007 | ☐ not verified |
| 3 | SEC-07's `FileProtectionType`: protection level and backup-exclusion flag have no observable effect on the macOS test host; needs a real-device/simulator file-attribute check. | feat-002 | ☐ not verified |
| 4 | docs/02 §7 Fase 1 scenarios not covered by any automated test: disk full (real `ENOSPC`, not just the SDK's own size cap), and force-quit specifically *during* an in-flight upload (offline buffering itself is tested; the exact "killed mid-HTTP-request" timing is not). | feat-002, feat-005 | ☐ not verified |
| 5 | Performance budget (docs/02 §5): app-size delta, cold-start overhead, CPU, memory, disk — needs measuring on a real device at all, automated or not. | Phase 1 (all); now filed as feat-012 | ☐ not verified |
| 6 | A forced crash captured by real KSCrash on iOS Simulator/device, appearing correctly after relaunch (feat-009's actual "Done when" criterion). | feat-009 | ☑ verified 2026-08-28 — `IOSCrashHarnessTests.phase1_forceCrash`/`phase2_readBackAfterRelaunch`, run via `xcodebuild test` against a booted iOS 18.0 Simulator; re-runnable any time per that file's header comment. |
| 7 | A real >2s main-thread block detected live by KSCrash's `Watchdog` monitor + `HangDetector`, without the detector itself blocking or hanging (MOB-18's actual "Done when"). | feat-010 | ☑ verified 2026-08-29 — `IOSCrashHarnessTests.phase3_hangDetection`, same Simulator/invocation pattern as item 6. |

Items 1–5 (feat-002/007/008, Phase 1) remain unverified as of 2026-08-29 — feat-009/010 added
their own device-only checks (6, 7) but did not re-visit these. Still the running punch list
before the pilot ships.

## Shipped

Completed epics, rotated to `archive/epics/`. One line each.

- **APM Kit iOS SDK** (2026-08-24 → 2026-08-29, 10/10 features) — Phase 1 (network
  observability) + Phase 2 (crash reporting, stability, remote control). Full detail:
  [archive/epics/apmkit-ios-sdk.md](archive/epics/apmkit-ios-sdk.md); requirement coverage +
  Android parity notes: [archive/epics/phase-1-2-wrap-up.md](archive/epics/phase-1-2-wrap-up.md).
