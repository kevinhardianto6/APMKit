# Features

> Scope backbone, grouped by epic (one epic = one PRD = one ID prefix).
> Status: 🟡 not started · 🔵 in progress · ✅ done · 🔴 blocked · 🟠 needs verification
> **One feature is active at a time per person** (see `state/<name>.md`) — the backlog may span epics.
> `By` = who actually did the work, from `git config user.name` on the machine that ran it.
> Completed feature detail → `archive/features/`. Completed *epics* → `archive/epics/`, listed under Shipped.

| Epic | Progress | Active / open |
|------|:--------:|---------------|
| APM Kit iOS SDK | 9/10 | feat-010 |

---

## Epic · APM Kit iOS SDK

**PRD:** `docs/02-Mobile-SDK.md` (+ `docs/01-Kontrak-Data-API.md` for schema/API contract,
`docs/00-Overview.md` for product context) · **Prefix:** `feat-`
**Scope:** Phase 1 (network observability) + Phase 2 (crash reporting) only. Phase 3
(backend, dashboard, symbolication service, sampling, public sample-app/docs) is explicitly
out of scope for this epic.
**Started:** 2026-08-24 · **Started by:** Kevin Hardianto

Build order is fixed by dependency (see `CONSTITUTION.md` → Prohibitions — process). One
feature per branch/PR; stop for review after each.

| ID | Feature | Status | By | Depends on | Requirements | Evidence |
|----|---------|:------:|----|------------|--------------|----------|
| feat-001 | Core & Envelope | ✅ | Kevin Hardianto | — | schema §2–5 (01) | [archive](archive/features/feat-001.md) |
| feat-002 | Disk Queue | ✅ | Kevin Hardianto | feat-001 | MOB-04/05/06, SEC-07 | [archive](archive/features/feat-002.md) |
| feat-003 | Network Capture | ✅ | Kevin Hardianto | feat-001, feat-002 | MOB-01/02/03/10, MOB-02b | [archive](archive/features/feat-003.md) |
| feat-004 | Scrubbing | ✅ | Kevin Hardianto | feat-003 | SEC-01..05b | [archive](archive/features/feat-004.md) |
| feat-005 | Sync Engine | ✅ | Kevin Hardianto | feat-002, feat-004 | MOB-07/08/09 | [archive](archive/features/feat-005.md) |
| feat-006 | Identifier & Manual API | ✅ | Kevin Hardianto | feat-001, feat-004 | MOB-28, SEC-06 | [archive](archive/features/feat-006.md) |
| feat-007 | Breadcrumbs | ✅ | Kevin Hardianto | feat-004, feat-006 | MOB-11/12/13 | [archive](archive/features/feat-007.md) |
| feat-008 | Device Integrity | ✅ | Kevin Hardianto | feat-001 | MOB-29/30/31 | [archive](archive/features/feat-008.md) |
| feat-009 | Crash Reporting (KSCrash) | ✅ | Kevin Hardianto | feat-001..008 | MOB-15/16/17 | [archive](archive/features/feat-009.md) |
| feat-010 | Stability + Remote Control | 🟡 | — | feat-005, feat-009 | MOB-18/19/20/21/27 | — |

> feat-001..008 = end of Phase 1 (SDK shippable for network observability). feat-009/010 =
> Phase 2.

> **Phase 1 complete 2026-08-28** (feat-001..008, all ✅). Wrap-up — MOB-/SEC- coverage,
> deferrals, and the running manual-device-verification list — recorded in
> `archive/epics/phase-1-wrap-up.md`.

> **feat-009 complete 2026-08-28** (3 PRs — install/pipeline, macOS-host verification, real
> iOS Simulator verification). Full detail: `archive/features/feat-009.md`.

---

### feat-010 · Stability + Remote Control

- **Status:** 🟡 not started · **Depends on:** feat-005, feat-009
- **Requirements:** main-thread hang detection (>2s), cold-start metric, remote config fetch
  (cached fallback) + kill switch (`enabled: false` disables SDK without app release), SDK
  self-health counters (events written vs sent vs dropped). MOB-18/19/20/21/27.
- **Done when:** kill switch disables SDK from server; hang events fire; self-health reported
  (tests).

**Decisions** — none yet. **Blockers** — none.

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
| 5 | Performance budget (docs/02 §5): app-size delta, cold-start overhead, CPU, memory, disk — needs measuring on a real device at all, automated or not. | Phase 1 (all) | ☐ not verified |
| 6 | A forced crash captured by real KSCrash on iOS Simulator/device, appearing correctly after relaunch (feat-009's actual "Done when" criterion). | feat-009 | ☑ verified 2026-08-28 — `IOSCrashHarnessTests` (`Tests/APMKitTests/Crash/`), run via `xcodebuild test` against a booted iOS 18.0 Simulator; re-runnable any time per that file's header comment. |

## Shipped

Completed epics, rotated to `archive/epics/`. One line each.

_None yet._
