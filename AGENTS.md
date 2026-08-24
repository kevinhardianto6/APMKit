# AGENTS.md

APMKit — in-house iOS Application Performance Monitoring SDK (crash reporting + network
observability). Write-local-first, sync-later: every event hits disk before any network call.
Router for agent work. Facts live in the linked docs; this file is the map, not the manual.

## Session startup

1. Load the `edts-harness` skill first, every session.
2. Read **your** state file — resolve it with:
   `echo "state/$(git config user.name | tr "[:upper:] " "[:lower:]-").md"`
   It's the only state file you read in full: active feature, last verify
   result, blockers, next step. Never write to anyone else's state file.
3. Read `CONSTITUTION.md` — the permanent rules and past decisions. Always in context.
4. Read `docs/00-Overview.md`, `docs/01-Kontrak-Data-API.md`, `docs/02-Mobile-SDK.md` — these
   are the **authoritative spec**. If anything in this repo's own docs conflicts with them,
   the spec wins.
5. Run `./verify.sh build` to confirm a clean baseline before editing.
6. Pick the **one** ready feature from `FEATURES.md` (all its `Depends on` are ✅).
   Set its status to 🔵 and start. Features are pre-ordered F1→F10 by dependency — do not
   jump ahead in the sequence.

## Project overview

- **Stack:** Swift Package (SPM), product `APMKit`. iOS 15+, Swift 5.9+ (tools 5.9, toolchain
  is Swift 6.3 / Xcode 26.4).
- **Structure:** `Sources/APMKit` (library target), `Tests/APMKitTests` (Swift Testing).
  No app target — this repo produces only the SDK.
- **Dependencies:** none for Phase 1 (Foundation/Network/Compression only). Phase 2 crash
  reporting (feat-009) is the sole feature allowed to add one: KSCrash.
- **Docs:** `docs/*.md` (spec, source of truth), `CONSTITUTION.md` (rules), `FEATURES.md`
  (scope), `JOURNAL.md` (lessons).

## Verification

Run before claiming any work done. All checks must pass.

```bash
./verify.sh build
./verify.sh test
```

`verify.sh` wraps `swift build` / `swift test` and prints a final `HARNESS_VERIFY: PASS` /
`FAIL` line — that line is your evidence. It builds/tests for the **host (macOS)** toolchain;
it does not target an iOS Simulator. If a feature introduces iOS-only API (UIKit lifecycle
notifications, `TARGET_OS_SIMULATOR`, etc.) that fails to compile on macOS, flag it — the
verify strategy may need to move to `xcodebuild test -scheme APMKit -destination 'platform=iOS
Simulator,name=<device>'` at that point rather than plain `swift build`/`swift test`. Do not
silently paper over a host-only compile failure with `#if os(iOS)` unless the spec calls for
platform-conditional behavior.

Only checks this project actually has are listed. Do not invent lint/e2e steps.

## Definition of done

A feature is `✅` only when: its `Done when` criteria are met, `verify.sh` passes, evidence is
recorded in its `FEATURES.md` sub-table, and your state file is updated with the next step.
Per the spec's build order, each feature is also its own PR/branch — do not start the next
feature until the current one has been reviewed.

## Session handoff

- Keep your state file current in real time — flip status the moment it changes.
- After every edit, append to its `Changes` table (file · what · why).
- Before ending: run verify, record the result, leave your state file resumable on its own.
- When a feature closes, rotate its detail to `archive/features/<id>.md` and replace its
  Evidence cell with a link. Same for sessions and completed epics. Write the archive file
  *first*, then remove the detail — the other order loses the evidence if interrupted.

---

## Rules

**All binding rules live in `CONSTITUTION.md`** — architecture, platform constraints, code
prohibitions, process, and git. It is binding, not advisory: read it at startup (step 3),
and if anything in this file appears to conflict with it, **`CONSTITUTION.md` wins.**

Rules are deliberately not repeated here. One home, no drift.
