# Epic · APM Kit iOS SDK

**Status:** ✅ shipped · closed 2026-08-29 · 10/10 features done.

Full requirement-by-requirement coverage (every MOB-/SEC- ID), what's deferred to Phase 3,
the manual verification checklist, and Android-parity notes: `archive/epics/phase-1-2-wrap-up.md`.
Phase 1's own narrower wrap-up (written at feat-008's close, before Phase 2 existed):
`archive/epics/phase-1-wrap-up.md`.

**PRD:** `docs/02-Mobile-SDK.md` (+ `docs/01-Kontrak-Data-API.md` for schema/API contract,
`docs/00-Overview.md` for product context) · **Prefix:** `feat-`
**Scope:** Phase 1 (network observability) + Phase 2 (crash reporting) only. Phase 3
(backend, dashboard, symbolication service, sampling, public sample-app/docs) was explicitly
out of scope for this epic from the start.
**Started:** 2026-08-24 · **Started by:** Kevin Hardianto · **Closed:** 2026-08-29

Build order was fixed by dependency (see `CONSTITUTION.md` → Prohibitions — process). One
feature per branch/PR, reviewed after each — held for all 10 features.

| ID | Feature | Status | By | Depends on | Requirements | Evidence |
|----|---------|:------:|----|------------|--------------|----------|
| feat-001 | Core & Envelope | ✅ | Kevin Hardianto | — | schema §2–5 (01) | [archive](../features/feat-001.md) |
| feat-002 | Disk Queue | ✅ | Kevin Hardianto | feat-001 | MOB-04/05/06, SEC-07 | [archive](../features/feat-002.md) |
| feat-003 | Network Capture | ✅ | Kevin Hardianto | feat-001, feat-002 | MOB-01/02/03/10, MOB-02b | [archive](../features/feat-003.md) |
| feat-004 | Scrubbing | ✅ | Kevin Hardianto | feat-003 | SEC-01..05b | [archive](../features/feat-004.md) |
| feat-005 | Sync Engine | ✅ | Kevin Hardianto | feat-002, feat-004 | MOB-07/08/09 | [archive](../features/feat-005.md) |
| feat-006 | Identifier & Manual API | ✅ | Kevin Hardianto | feat-001, feat-004 | MOB-28, SEC-06 | [archive](../features/feat-006.md) |
| feat-007 | Breadcrumbs | ✅ | Kevin Hardianto | feat-004, feat-006 | MOB-11/12/13 | [archive](../features/feat-007.md) |
| feat-008 | Device Integrity | ✅ | Kevin Hardianto | feat-001 | MOB-29/30/31 | [archive](../features/feat-008.md) |
| feat-009 | Crash Reporting (KSCrash) | ✅ | Kevin Hardianto | feat-001..008 | MOB-15/16/17 | [archive](../features/feat-009.md) |
| feat-010 | Stability + Remote Control | ✅ | Kevin Hardianto | feat-005, feat-009 | MOB-18/19/20/21/27 | [archive](../features/feat-010.md) |

feat-001..008 = Phase 1 (SDK shippable for network observability), closed 2026-08-28.
feat-009/010 = Phase 2 (crash reporting + stability/remote control), closed 2026-08-29.

**Note:** the epic being "shipped" here means its 10 filed features are done — it does **not**
mean the SDK is pilot-ready. `phase-1-2-wrap-up.md`'s "Real gaps" and "Manual verification
checklist" sections list what's still open (SEC-08/10/11/12/14, the performance budget,
MOB-22/23/24/26, and 5 of 7 manual-verification items) before a rollout to other teams.
