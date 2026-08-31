# Epic · Pre-Pilot Hardening

**Status:** ✅ shipped 2026-08-29 → 2026-08-31, 6/6 features.

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
P2 and opt-in, the lowest-urgency item in the epic; composition root last, deliberately after
feat-014/015 — it should assemble and wire the pipeline these already-built pieces produce
(including feat-015's pinning config), not be built before they exist and then patched. Build
order is otherwise the same mandatory rule as before (`CONSTITUTION.md` → Prohibitions —
process): one feature active at a time, stop for review after each.

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
> root cause — no app in this repo to integrate into or test against. feat-016 explicitly
> included building a **minimal internal verification app** (not MOB-25's own
> published/maintained sample app) as part of its own scope, since its "Done when" already
> needed one. The `.xcodeproj` spike was done early, per plan, and landed on the first real
> attempt — see `archive/features/feat-016.md` for the full account, including the resulting
> real verification of manual checklist item 9 (Keychain persistence) and the unblocking (not
> full closure — Simulator ≠ real device) of item 5 (cold-start).

| ID | Feature | Status | By | Depends on | Requirements | Evidence |
|----|---------|:------:|----|------------|--------------|----------|
| feat-011 | TLS Floor + Fail-Closed | ✅ | Kevin Hardianto | feat-005, feat-010 | SEC-10, SEC-12 | [archive](../features/feat-011.md) |
| feat-012 | Performance Budget (CI-enforced) | ✅ | Kevin Hardianto | feat-001..010 | docs/02 §5 | [archive](../features/feat-012.md) |
| feat-013 | Distribution (CocoaPods + semver) | ✅ | Kevin Hardianto | feat-001..010 | MOB-23/24 | [archive](../features/feat-013.md) |
| feat-014 | At-Rest Queue Encryption | ✅ | Kevin Hardianto | feat-002 | SEC-08 | [archive](../features/feat-014.md) |
| feat-015 | Optional Certificate Pinning (opt-in, P2) | ✅ | Kevin Hardianto | feat-011, feat-010 | SEC-11 | [archive](../features/feat-015.md) |
| feat-016 | Composition Root (`APM.start`) | ✅ | Kevin Hardianto | feat-014, feat-015 | MOB-25 (integration-time risk) | [archive](../features/feat-016.md) |

## Wrap-up

All six features closed with real evidence, no shortcuts taken on the "prove it for real"
standard this project holds itself to (feat-011's TLS-layer failure, feat-012's binary-size
measurement, feat-013's CocoaPods lint, feat-014's Keychain round-trip, feat-015's real TLS
handshakes against hand-generated self-signed certs, feat-016's real installed-app
verification). Two genuine test-infrastructure bugs were found and fixed along the way (not
production bugs): a mock-server request race (feat-015) and a Keychain-contention flake across
`swift test`'s parallel execution that feat-015's own new test infra surfaced in feat-014's
pre-existing suite (fixed with a shared `KeychainTestLock`).

Manual verification checklist items 6 and 7 (feat-009/010, crash/hang) were already verified
before this epic started. This epic additionally verified item 9 (feat-016, Keychain
persistence) and unblocked-but-not-closed item 5 (feat-016, cold-start — needs real device).
Items 1–4 and 8 remain open; see `FEATURES.md`'s manual verification checklist for the current
state of those.

Android port is unblocked now that this epic is closed — see
`archive/epics/phase-1-2-wrap-up.md` → "What an Android port would need for parity."
