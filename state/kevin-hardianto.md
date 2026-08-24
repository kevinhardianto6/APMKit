# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** Build the APM Kit iOS SDK (Phase 1 network observability + Phase 2 crash
  reporting), per docs/00-02. Repo just converted from Xcode framework scaffold to a real SPM
  package (Package.swift, Sources/APMKit, Tests/APMKitTests).
- **Active feature:** feat-001 · Core & Envelope
- **Status:** 🟠 needs verification — implemented + tested, stopped per build-order rule to
  wait for review before starting feat-002 (Disk Queue).
- **Last verify:** `./verify.sh all` → `HARNESS_VERIFY: PASS (all)`, 2026-08-24 (15 tests).

## Next step

Awaiting review of feat-001. On approval: mark ✅ in FEATURES.md, rotate detail to
`archive/features/feat-001.md`, then start feat-002 (Disk Queue, MOB-04/05/06) — a protocol-
based local-first store, atomic write, 20MB/5000-event cap with FIFO eviction, survives
process kill / force-quit / restart.

## Parked

- None.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

| File | Change | Why |
|------|--------|-----|
| `docs/*.md` | Added (copied from spec source) | Versioned source of truth for MOB-/SEC- reqs |
| `Package.swift`, `Sources/`, `Tests/` | Added; removed `APMKit.xcodeproj`/`APMKitTests` | Spec deliverable is SPM, not an Xcode framework project |
| `verify.sh` | Rewritten for `swift build`/`swift test` | Matches new SPM structure |
| `AGENTS.md`, `CONSTITUTION.md`, `FEATURES.md` | Updated | Reflect SPM/iOS15, pipeline invariants, F1-F10 backlog |
| `.gitignore` | Added | `.build/`, `.swiftpm/` were showing as untracked noise |
| `Sources/APMKit/Core/*.swift` (10 files) | Added | feat-001: Envelope, Event, DeviceInfo, SDKInfo/AppInfo, IntegritySnapshot (stub), EventContext, AttributeValue, ISO8601Formatting, InstallIdentity, SessionManager |
| `Tests/APMKitTests/Core/*.swift` (4 files) | Added | feat-001 unit tests — 15 tests, all passing |
| `Tests/APMKitTests/APMKitTests.swift` | Removed | Placeholder scaffold test superseded by real feat-001 tests |
| `FEATURES.md` | feat-001 → 🟠 needs verification | Done-when criteria met, evidence recorded |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
