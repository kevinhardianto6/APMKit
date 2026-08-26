# Features

> Scope backbone, grouped by epic (one epic = one PRD = one ID prefix).
> Status: 🟡 not started · 🔵 in progress · ✅ done · 🔴 blocked · 🟠 needs verification
> **One feature is active at a time per person** (see `state/<name>.md`) — the backlog may span epics.
> `By` = who actually did the work, from `git config user.name` on the machine that ran it.
> Completed feature detail → `archive/features/`. Completed *epics* → `archive/epics/`, listed under Shipped.

| Epic | Progress | Active / open |
|------|:--------:|---------------|
| APM Kit iOS SDK | 4/10 | — |

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
| feat-005 | Sync Engine | 🟡 | — | feat-002, feat-004 | MOB-07/08/09 | — |
| feat-006 | Identifier & Manual API | 🟡 | — | feat-001, feat-004 | MOB-28, SEC-06 | — |
| feat-007 | Breadcrumbs | 🟡 | — | feat-004, feat-006 | MOB-11/12/13 | — |
| feat-008 | Device Integrity | 🟡 | — | feat-001 | MOB-29/30/31 | — |
| feat-009 | Crash Reporting (KSCrash) | 🟡 | — | feat-001..008 | MOB-15/16/17 | — |
| feat-010 | Stability + Remote Control | 🟡 | — | feat-005, feat-009 | MOB-18/19/20/21/27 | — |

> feat-001..008 = end of Phase 1 (SDK shippable for network observability). feat-009/010 =
> Phase 2. feat-009 may span several PRs (sub-split as needed) — do not rush the crash handler.

### feat-005 · Sync Engine

- **Status:** 🟡 not started · **Depends on:** feat-002, feat-004
- **Requirements:** batched upload (≤200 events/≤1MB gzip via Compression) on timer,
  background transition, connectivity restore; exponential backoff. Exact response contract
  (`01` §7): 202 delete, 400 drop (no infinite retry), 401/403 pause 24h, 413 split, 429 honor
  Retry-After, 5xx backoff+keep. Delete local events only after 2xx. Separate non-instrumented
  `URLSession`; ingest host excluded from capture (anti-loop). MOB-07/08/09.
- **Done when:** buffers offline, flushes on reconnect; every response code handled; no
  instrumentation loop (tests w/ mock server).

**Decisions** — none yet. **Blockers** — none.

---

### feat-006 · Identifier & Manual API

- **Status:** 🟡 not started · **Depends on:** feat-001, feat-004
- **Requirements:** `APM.setUser(id:)` takes any free-form string, sent **raw** in
  `envelope.user_id` over TLS, never hashed client-side (hashing to `user_ref` is backend's
  job). Fallback: stable random id persisted per install if never set. Raw `user_id` must
  never leak into breadcrumbs/logs/other fields. Also `APM.logError`. MOB-28, SEC-06.
- **Done when:** raw `user_id` present in envelope, never leaks elsewhere; fallback stable
  per install (tests).

**Decisions** — none yet. **Blockers** — none.

---

### feat-007 · Breadcrumbs

- **Status:** 🟡 not started · **Depends on:** feat-004, feat-006
- **Requirements:** `APM.breadcrumb(_:category:)` + automatic (screen/lifecycle/connectivity);
  ring buffer of last 100 attached to each error event. MOB-11/12/13.
- **Done when:** ring buffer attaches to errors; auto-crumbs fire (tests).

**Decisions** — none yet. **Blockers** — none.

---

### feat-008 · Device Integrity

- **Status:** 🟡 not started · **Depends on:** feat-001
- **Requirements:** snapshot once per session into `envelope.integrity`: `is_emulator`
  (`TARGET_OS_SIMULATOR`/env), `is_rooted` (jailbreak file checks + sandbox-write test +
  suspicious symlinks), `is_dev_mode` (debugger via `sysctl` `P_TRACED` + non-App-Store build
  via `embedded.mobileprovision`/TestFlight `sandboxReceipt`), `debugger_attached`. Heuristic
  only — no privileged APIs (no IMEI). MOB-29/30/31.
- **Done when:** flags correct on real device + simulator (manual verification required —
  simulator-only automation can't fully prove real-device jailbreak/dev-mode detection).

**Decisions** — none yet. **Blockers** — none.

---

### feat-009 · Crash Reporting (KSCrash)

- **Status:** 🟡 not started · **Depends on:** feat-001, feat-002, feat-003, feat-004,
  feat-005, feat-006, feat-007, feat-008 (end of Phase 1)
- **Requirements:** wrap KSCrash (do not hand-roll signal/mach handlers). On crash, write a
  minimal report to disk (no PII), send on next launch; include `binary_images` + UUIDs for
  later symbolication. MOB-15/16/17. May span several PRs — sub-split as needed; this is the
  highest-risk feature (crash handler is the sole component intentionally running during a
  crash, per `CONSTITUTION.md`).
- **Done when:** a forced crash is captured and appears in the mock backend after relaunch;
  raw on-disk report is minimal (no PII) — see docs/02 §6.2 trade-off box on why the raw crash
  report is unencrypted at write time.

**Decisions** — none yet. **Blockers** — none.

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

## Shipped

Completed epics, rotated to `archive/epics/`. One line each.

_None yet._
