# Constitution — APMKit

> **Binding.** This file owns every rule in the project. `AGENTS.md` describes *how to work*;
> this file defines *what is always true*. On any conflict, this file wins. Where this file and
> `docs/*.md` (the PRD/spec) disagree, **the spec wins** — amend this file to match it, don't
> silently follow the older rule.
> Never archived, always in context. Changing a rule is a deliberate amendment — date it.

## Invariants — architecture

- **Pipeline order is fixed and never reversed:** Capture → Scrub → Disk → Sync. Scrubbing
  (PII redaction) runs as the **last** step before every disk write, including for data
  entered through manual APIs (`logError`, `breadcrumb`). Nothing reaches disk unscrubbed.
- **Write-local-first:** every event is durably written to disk before any network call is
  attempted. The sync engine only ever reads from and deletes from the disk queue — it never
  holds events solely in memory pending upload.
- **Local events are deleted only after a 2xx response** from `POST /v1/ingest`. This is what
  makes at-least-once delivery hold; deleting pre-ACK loses data on every mid-upload
  disconnect.
- **The uploader is a separate, non-instrumented `URLSession`** from the one exposed to host
  apps via `APM.instrumentedSession()`, and the ingest host is excluded from capture. Capturing
  the SDK's own upload traffic creates an infinite instrumentation loop.
- **`user_id` is transported raw, never hashed client-side.** Hashing to `user_ref` is the
  backend's job (BE-21) — the SDK's only obligation is that the raw value occupies exactly the
  `user_id` envelope slot and never leaks into breadcrumbs, logs, or any other field.

## Invariants — platform

- **Deployment target: iOS 15.0.** Check API availability before using any newer
  SwiftUI/UIKit/Foundation API. Toolchain is Swift 6.3 / Xcode 26.4 (tools-version 5.9 in
  `Package.swift`).
- **This is a Swift Package, not an Xcode project.** No `.xcodeproj`/`.xcworkspace` in this
  repo — build and test via `swift build` / `swift test` (or `./verify.sh`). If iOS-only APIs
  ever make host-toolchain (`swift test` on macOS) compilation fail, that's a signal to add an
  `xcodebuild test -destination 'platform=iOS Simulator,...'` path in `verify.sh`, not to work
  around it with conditional compilation the spec doesn't call for.
- **Dependencies are minimal by design.** Phase 1 (feat-001..008): Foundation, Network,
  Compression only — zero third-party deps. Phase 2 crash reporting (feat-009) is the *only*
  feature permitted to add a dependency, and it must be KSCrash (deliberate: wrap a mature
  crash library rather than hand-roll signal/mach handlers — see docs/02 §3.5). No other
  feature adds a dependency without a new dated decision here.
- **No dynamic code execution.** Remote config (feat-010) may only toggle predefined flags; it
  must never change executable behavior (SEC-20).

## Prohibitions — code

- No `print()` — use `OSLog` if logging is genuinely needed, and only in debug builds
  (MOB-26 debug mode must be inert in release).
- No force unwraps (`!`), force casts (`as!`), or `try!` in SDK code. Test mocks excepted.
- **The SDK must never crash or throw into the host app — this is rule #1.** Every public
  entry point and every internal callback must be defensive: catch, count via the self-health
  counters (feat-010 / MOB-27), and fail silently. The only intentional exception is the crash
  handler itself (feat-009), which by definition runs during a crash. Internal disk I/O
  failures must never throw to the caller; response parsing must never assume a payload shape.
- Never weaken ATS / ship a way to disable TLS 1.2+ (SEC-10). Certificate pinning failures
  fail closed — data stays on disk, never falls back to an unpinned connection (SEC-12).
- Header capture uses an **allowlist** (`Content-Type`, `Content-Length`, `Accept`,
  `User-Agent`) — never a blocklist. `Authorization`/`Cookie`/custom headers are never
  recorded, full stop (SEC-02).
- Request/response bodies are never captured; there is no opt-in for it (SEC-04).

## Prohibitions — process

- **Never auto-commit.** Update files, report what changed, let the user decide.
- Never mark a feature ✅ without evidence recorded in `FEATURES.md`.
- One feature active at a time per person (see your `state/<name>.md`). Out-of-scope ideas
  become new `FEATURES.md` rows, not drive-by edits.
- **Build order (F1→F10 in `FEATURES.md`) is mandatory, not a suggestion.** Each feature is
  its own branch/PR: implement, keep it compiling, add its unit tests, stop for review. Do not
  start the next feature in the sequence before the current one is reviewed, even if it looks
  quick.

## Git

- Base branch for PRs: `main`. Feature branches: `feature-<topic>/<detail>`.
- **Commit messages are prefixed with the feature ID:** `feat-001: <summary>`.
  This lets `git log --grep="<id>"` corroborate the `By` column in `FEATURES.md` — markdown
  gives attribution at a glance, git proves it.
- **State is one file per person:** `state/<git config user.name>.md`. You write only your own
  file; nobody else ever touches it. Because git only conflicts when two branches change the
  *same lines of the same file*, this makes **merge, rebase and cherry-pick conflict-free by
  construction** — no merge strategy, no `.gitattributes`, no per-developer setup to forget.
- **Cross-person visibility lives in `FEATURES.md`, not in state files.** `FEATURES.md` merges
  normally and shows every in-flight feature with its `By` owner. Your state file answers only
  "what am *I* doing right now." Keep a short **In flight elsewhere** note when a teammate
  picks up work you care about.
- Attribution (`By` columns, journal authors) comes from `git config user.name` on the machine
  running the session — never from the agent, so it works identically for any tool.

---

## Decisions

_Dated entries. Add one whenever an arguable choice gets settled — include the reasoning, so
it can be reopened later without redoing the analysis. Amend by adding a new dated entry that
supersedes the old one; never silently edit history._

### 2026-08-24 · SPM package, not Xcode framework project

Repo was scaffolded by `edts-harness` as an Xcode `.xcodeproj` framework target (default
template), but the spec (docs/02-Mobile-SDK.md §"Deliverable") calls for a Swift Package.
Converted: removed `APMKit.xcodeproj`/`APMKitTests` bundle, added `Package.swift`,
`Sources/APMKit`, `Tests/APMKitTests` (Swift Testing). `verify.sh` now runs `swift build` /
`swift test` instead of `xcodebuild`. Reason: matches MOB-23 (distribution via SPM &
CocoaPods) and avoids maintaining a parallel Xcode project that isn't the actual deliverable.

### 2026-08-28 · feat-009: KSCrash monitor selection excludes Watchdog/hang

`KSCrashMonitorTypeProductionSafeMinimal` (the sane default) includes `Watchdog`, which is
KSCrash's built-in main-thread-hang detector — exactly what MOB-18 asks for. But MOB-18 is
`FEATURES.md`'s feat-010 requirement, not feat-009's, and this project's build order is
mandatory (Prohibitions — process, above): one feature active at a time, no drive-by scope
creep into a later row. feat-009 installs `machException, signal, cppException, nsException,
userReported, termination` and leaves `Watchdog` off; feat-010 turns it on. `CrashReportMapper`
still decodes `crash_type: hang` defensively so that flip is the only change feat-010 needs to
make here. Full reasoning: `FEATURES.md` → feat-009 → Decisions.

### 2026-08-24 · Deployment target iOS 15

The harness's auto-probe picked up the *host* Xcode's default (`IPHONEOS_DEPLOYMENT_TARGET =
26.4`), which is not an intentional product decision — it's just what a fresh Xcode project
defaults to on this machine. Spec says "iOS 15+, adjust to our deployment target" with no
stricter constraint given. Chose iOS 15 as the floor: broad compatibility for an
internally-adopted SDK, and sufficient for async/await, `Compression` framework APIs (F5), and
`URLSessionTaskMetrics` (F3). Revisit if an adopter team needs a stricter floor.
