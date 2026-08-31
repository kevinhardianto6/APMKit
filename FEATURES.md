# Features

> Scope backbone, grouped by epic (one epic = one PRD = one ID prefix).
> Status: 🟡 not started · 🔵 in progress · ✅ done · 🔴 blocked · 🟠 needs verification
> **One feature is active at a time per person** (see `state/<name>.md`) — the backlog may span epics.
> `By` = who actually did the work, from `git config user.name` on the machine that ran it.
> Completed feature detail → `archive/features/`. Completed *epics* → `archive/epics/`, listed under Shipped.

| Epic | Progress | Active / open |
|------|:--------:|---------------|
| Pre-Pilot Hardening | 5/6 | feat-016 |

---

## Epic · Pre-Pilot Hardening

**PRD:** `docs/02-Mobile-SDK.md` §5–6 (performance budget, client-side security) — no separate
PRD document; this epic remediates P0/P1/P2 requirements from the existing spec that the
shipped APM Kit iOS SDK epic left unfiled, surfaced by that epic's own wrap-up
(`archive/epics/phase-1-2-wrap-up.md` → "Real gaps"). **Prefix:** `feat-` (continues the same
sequence — one SDK, one PRD family, no reason to fork numbering for a remediation pass).
**Scope:** SEC-10/11/12 (TLS floor, fail-closed, optional pinning), the docs/02 §5 performance
budget, MOB-23/24 (distribution), SEC-08 (at-rest encryption), and (added 2026-08-31) a
composition root — feat-016 isn't itself a numbered docs/02 requirement; it's the user's
direct response to a real risk feat-013 surfaced against MOB-25's integration-time target, so
it belongs in this pre-pilot epic rather than waiting for MOB-25 itself (Phase 3). Explicitly
**not** in scope: Android (blocked on this epic per the user's own sequencing — parity notes
are ready in the wrap-up above, Android work starts after), MOB-22 (sampling), SEC-14 (key
rotation), MOB-26 (debug logging) — those remain unfiled gaps, not silently rolled into this
epic.
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
SDK at all; at-rest encryption fourth because it can trail; optional pinning fifth because it's
P2 and opt-in, the lowest-urgency item in the epic; **composition root last, deliberately after
feat-014/015** — it should assemble and wire the pipeline these already-built pieces produce
(including feat-015's pinning config, if enabled), not be built before they exist and then
patched. Build order is otherwise the same mandatory rule as before (`CONSTITUTION.md` →
Prohibitions — process): one feature active at a time, stop for review after each.

> **2026-08-30, feat-013:** found and fixed a real CocoaPods/SPM incompatibility — CocoaPods'
> `KSCrash` pod exposes one umbrella module (`import KSCrash`), not per-subspec modules like
> SPM (`import KSCrashRecording`); every KSCrash-touching file now imports conditionally on
> `canImport(KSCrashRecording)`. Also flagged, not fixed (out of this feature's scope): **the
> SDK has no composition root** — a from-scratch integration needs roughly a dozen manually-
> wired pieces before the first event is captured, a real risk to MOB-25's "under 30 minutes"
> target. See `VERSIONING.md` → "Integration friction" and `archive/features/feat-013.md`.
>
> **2026-08-31:** the composition-root flag above got a feature, not a deferral — **feat-016**,
> scheduled before the pilot rather than left for MOB-25/Phase 3. User's reasoning: MOB-25's
> 30-minute target is part of what the pilot is meant to test, not a nice-to-have; hand-
> assembling a dozen components tests the integrator's patience, not the SDK. Every manual
> wiring step is also a repeat of a risk class this project has already closed twice by making
> forgetting structurally impossible instead of relying on integrator memory — feat-005's
> anti-loop guarantee (MOB-09/10) and feat-009's pending-crash-report drain
> (`installCrashReporting` folding in what used to be a separate `processPendingCrashReports`
> call). A single correct entry point is the same fix shape, applied to the whole integration
> instead of one leak at a time.
>
> **2026-08-31, feat-014:** encryption itself proven for real (macOS Keychain round-trip, real
> AES-GCM round-trip, real on-disk ciphertext inspection, real Simulator write). What's
> **not** proven: true cross-app-relaunch Keychain persistence — `xcodebuild test`'s XCTest
> infrastructure resets Keychain state between separate invocations regardless of app-binary
> identity (root-caused via `simctl spawn log show`), so the two-phase harness technique that
> worked for feat-009's crash reports doesn't transfer to Keychain. Same underlying gap as
> feat-012's cold-start reasoning and feat-013's composition-root finding: **no sample host
> app exists in this repo** to install-and-relaunch for real instead of via XCTest. Added to
> the manual checklist (item 9) rather than claimed proven. Also fixed two **pre-existing**
> iOS-15-floor violations (`Data.contains`, Swift `Regex`) that only a real Simulator build —
> not `swift test` on macOS — could have caught; one was in already-committed feat-013 work.
>
> **2026-08-31, feat-016 scope decision:** the three findings above (feat-012 cold-start,
> feat-013 composition-root friction, feat-014 Keychain persistence) all trace to the same
> root cause — no app in this repo to integrate into or test against. Rather than re-derive
> that three times, feat-016 now explicitly includes building a **minimal internal
> verification app** (not MOB-25's own published/maintained sample app — see feat-016's entry
> for the distinction) as part of its own scope, since its "Done when" already needed one.
> Spike the `.xcodeproj` cost early and report back before building further on it.

| ID | Feature | Status | By | Depends on | Requirements | Evidence |
|----|---------|:------:|----|------------|--------------|----------|
| feat-011 | TLS Floor + Fail-Closed | ✅ | Kevin Hardianto | feat-005, feat-010 | SEC-10, SEC-12 | [archive](archive/features/feat-011.md) |
| feat-012 | Performance Budget (CI-enforced) | ✅ | Kevin Hardianto | feat-001..010 | docs/02 §5 | [archive](archive/features/feat-012.md) |
| feat-013 | Distribution (CocoaPods + semver) | ✅ | Kevin Hardianto | feat-001..010 | MOB-23/24 | [archive](archive/features/feat-013.md) |
| feat-014 | At-Rest Queue Encryption | ✅ | Kevin Hardianto | feat-002 | SEC-08 | [archive](archive/features/feat-014.md) |
| feat-015 | Optional Certificate Pinning (opt-in, P2) | ✅ | Kevin Hardianto | feat-011, feat-010 | SEC-11 | [archive](archive/features/feat-015.md) |
| feat-016 | Composition Root (`APM.start`) | 🟡 | — | feat-014, feat-015 | MOB-25 (integration-time risk) | — |

### feat-016 · Composition Root (`APM.start`)

- **Status:** 🟡 not started · **Depends on:** feat-014 (at-rest encryption — the disk queue
  this assembles needs to be the encrypted one), feat-015 (pinning config — `APM.start`'s
  config surface needs to include the opt-in pinning knob, not be built before it exists and
  patched afterward)
- **Requirements (per the user, 2026-08-31):**
  - One `APM.start(configuration:)` that assembles and wires the pipeline correctly *by
    construction* — `SessionManager`, `FileDiskQueue`, `Scrubber`/`KillSwitch` chain,
    `EnvelopeFactory`, `IngestClient`/`SyncEngine` with its background/connectivity triggers
    actually wired to real `UIApplication`/`NWPathMonitor` notifications (not left for the
    integrator to remember, the same class of gap `AutomaticBreadcrumbSource` already leaves
    open today), crash reporting, hang detection, remote config fetch.
  - The existing granular types (`SessionManager`, `FileDiskQueue`, `IngestClient`,
    `SyncEngine`, every `APM.*` call, …) **stay public** for advanced/custom use — this is an
    additive convenience layer, not a replacement that locks anyone out of the pieces.
  - Same "make forgetting structurally impossible" shape as MOB-09/10's anti-loop guarantee
    (feat-005) and `installCrashReporting`'s pending-report drain (feat-009) — a single entry
    point that can't be assembled wrong, not documentation asking the integrator to remember
    a dozen steps in the right order.
- **Done when:** a from-scratch integration in a fresh project, timed, completes in under 30
  minutes following only the written docs — MOB-25's actual target, measured directly rather
  than assumed satisfied because a composition root exists. Not satisfied by unit tests alone.

> **2026-08-31, added after feat-014:** feat-016's own "Done when" (a timed integration) is
> unmeasurable without something to integrate *into* — so this feature includes building a
> **minimal app**, not just the `APM.start` API. Decided explicitly, not assumed:
> - **This is internal verification tooling, not MOB-25's deliverable.** Minimal, blank
>   single-screen, lives outside the SDK's own `Package.swift` (`AGENTS.md`'s "no app target"
>   stays true for the SDK) — same precedent as `scripts/size-budget/` and the feat-013
>   bare-clone consumer. MOB-25 ("Sample app + dokumen integrasi," docs/02 §3.7) is a
>   *published, maintained* reference other teams copy from, paired with a full integration
>   guide document — a documentation/DX deliverable, materially bigger than this. **feat-016
>   does not close MOB-25** — it gives Phase 3 something to evolve instead of starting from
>   zero, nothing more.
> - **Why now, not deferred to MOB-25/Phase 3:** three independent features
>   (feat-012's cold-start reasoning, feat-013's composition-root friction, feat-014's
>   Keychain-persistence finding) hit the identical wall — no app to integrate into or test
>   against. That's convergent signal, not coincidence; re-deriving it later would mean
>   re-discovering the same thing three separate times.
> - **Side effect, not a promise:** manual checklist items 5 (cold-start) and 9 (Keychain
>   relaunch persistence) are *expected* to become verifiable once this app exists, but are
>   **not pre-marked verified** — only actually check them off once the app is built and each
>   is run against it for real.
> - **Cost flag, spike before committing further:** every throwaway harness so far
>   (`scripts/size-budget`, the bare-clone consumer) has been a plain SPM package — no real
>   iOS app bundle needed. A genuinely installable app for the Keychain-relaunch case likely
>   needs an actual `.xcodeproj`, rougher to produce reliably from this environment than an
>   SPM manifest. **Spike this specifically, early in the feature, before building anything on
>   top of it** — if a reliable installable app turns out disproportionate to produce here,
>   say so and re-scope together rather than pushing through something fragile that needs
>   babysitting.

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
| 5 | Performance budget (docs/02 §5) — the part that isn't CI-measurable: CPU ≤2% average, memory ≤8MB resident, and cold-start overhead ≤30ms p95, each needing real-device profiling under realistic load (no sample host app exists to even attach a cold-start measurement to; CI runners are too noisy for a 30ms budget regardless). Binary size and main-thread I/O structural checks *are* now CI-gated (feat-012) — see `archive/features/feat-012.md` for the full reasoning split. | Phase 1 (all); split by feat-012 | ☐ not verified |
| 6 | A forced crash captured by real KSCrash on iOS Simulator/device, appearing correctly after relaunch (feat-009's actual "Done when" criterion). | feat-009 | ☑ verified 2026-08-28 — `IOSCrashHarnessTests.phase1_forceCrash`/`phase2_readBackAfterRelaunch`, run via `xcodebuild test` against a booted iOS 18.0 Simulator; re-runnable any time per that file's header comment. |
| 7 | A real >2s main-thread block detected live by KSCrash's `Watchdog` monitor + `HangDetector`, without the detector itself blocking or hanging (MOB-18's actual "Done when"). | feat-010 | ☑ verified 2026-08-29 — `IOSCrashHarnessTests.phase3_hangDetection`, same Simulator/invocation pattern as item 6. |
| 8 | The `.github/workflows/ci.yml` GitHub Actions workflow (feat-012) actually fires and gates a real PR — unverified in this environment because this repo has no git remote configured here. Its YAML is syntax-valid and it runs the same `./verify.sh all` already verified to pass locally. | feat-012 | ☐ not verified |
| 9 | True cross-app-relaunch Keychain persistence for SEC-08's encryption key (does the queue encrypted by one app launch still decrypt after the app is quit and relaunched — not via `xcodebuild test`, which resets Keychain state between invocations regardless of app identity, confirmed via `simctl spawn log show`). Needs a real installed app (device or `simctl install`/`launch` outside XCTest), which doesn't exist in this repo yet. | feat-014 | ☐ not verified |

Items 1–5 (feat-002/007/008, Phase 1) remain unverified as of 2026-08-31 — feat-009/010 added
their own device-only checks (6, 7) but did not re-visit these; feat-012 narrowed item 5's
scope but didn't close it. feat-014 added item 9, its own genuinely-unverified gap. Still the
running punch list before the pilot ships.

## Shipped

Completed epics, rotated to `archive/epics/`. One line each.

- **APM Kit iOS SDK** (2026-08-24 → 2026-08-29, 10/10 features) — Phase 1 (network
  observability) + Phase 2 (crash reporting, stability, remote control). Full detail:
  [archive/epics/apmkit-ios-sdk.md](archive/epics/apmkit-ios-sdk.md); requirement coverage +
  Android parity notes: [archive/epics/phase-1-2-wrap-up.md](archive/epics/phase-1-2-wrap-up.md).
