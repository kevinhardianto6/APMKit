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

### 2026-09-01 · MOB-30 Simulator false positive: skip the sandbox-write probe, don't loosen device logic

Pilot ingestion server's real traffic showed every clean Simulator session reporting
`integrity.is_rooted = true`. Cause: `DeviceIntegrityDetector.canWriteOutsideSandbox()` writes
to `/private/...` to detect a jailbroken sandbox escape, but the Simulator runs its whole
process unsandboxed on the host macOS — that write structurally always succeeds there, so the
probe proved nothing and always registered as a rooted signal. Two options considered:
(a) weaken `JailbreakVerdict.isRooted`'s combination logic generally, or (b) keep the
combination logic exactly as-is and only change what signal reaches it on Simulator. Chose
(b): `JailbreakVerdict.sandboxWriteSignal(isSimulator:rawWriteSucceeded:)` discards the raw
result specifically when `isSimulator` is true, and passes it through unchanged otherwise — a
real device's detection is byte-for-byte what it was before this fix. The file/symlink probes
were left alone (not routed through a similar Simulator skip) because a stock Simulator
filesystem doesn't carry jailbreak tooling paths and a hit there would still be a real signal,
not a structural false positive — though that reasoning rests on how Simulator's filesystem
happens to be laid out today, not a platform guarantee, so it stays on the manual verification
checklist (`FEATURES.md` item 1) rather than being treated as proven.

### 2026-09-01 · SIGKILL/termination reports dropped from `crash`, pending a spec decision

Pilot ingestion server's real traffic showed a `crash` event with `time_since_launch_ms: 581`
and an empty `reason` — traced to KSCrash's `Termination` monitor, which injects a synthetic
report (a fake `signal: SIGKILL` block "for backward compatibility") for OS-level kills that
can never be caught live: an Xcode Stop-button kill, the user swiping the app away, a rebuild,
or the system reclaiming memory. `CrashReportMapper` was mapping these to `crash_type: signal`
— not a crash by any real definition (nothing in app code caused or could catch it, and there
is no stack to symbolicate), and inflating crash counts, since nearly every dev session ends
this way. Sentry/Crashlytics both exclude SIGKILL from crash counts for the same reason.

**Investigated whether the cause is distinguishable** (can we tell an ordinary termination
from a real system-resource kill?): yes, partially. KSCrash's own `RunContext` classifies the
previous run's death into a `termination_reason` *before* the Termination monitor ever fires —
`memory_limit` / `memory_pressure` / `cpu` / `thermal` / `low_battery` are set only when that
specific critical resource state was actually observed in the last snapshot before death (a
real, evidence-based signal, not a guess); everything else — Xcode Stop, user swipe, rebuild,
plain `kill -9` — collapses into `unexplained`, because the OS genuinely gives no further
signal to KSCrash once a SIGKILL happens. So: system-resource kills are reliably
distinguishable from ordinary terminations; ordinary terminations are *not* further
distinguishable from each other, and `unexplained` should read as exactly that — "termination,
cause unknown" — not a guess dressed up as a diagnosis.

**Decision:** drop these reports from the `crash` pipeline now (`CrashReportMapper` returns
`nil` for `errorType == "termination"`) — this is a correctness fix that needs no schema
change, since it only stops a misclassification. Did **not** implement the richer "keep but
relabel" option (a new event type/attribute carrying `termination_reason`) — docs/01 §4.3
(`crash`) and §4.6 (`lifecycle`) have no field for it, and inventing wire schema the backend
doesn't know about isn't this SDK's call to make unilaterally. **Flagged as an open spec
question for the PRD owner:** should this become a new event type (e.g. `termination`, with
`termination_reason` and `is_fatal` attributes), or ride on the existing `lifecycle` type's
`terminate` state (§4.6) with an added attribute? Once docs/01 answers that, wiring the
emission is a small, well-scoped follow-up — the classification logic above is already worked
out, just not implemented against a type that doesn't exist yet.

### 2026-09-01 · Spec decision landed: `termination` is a new event type (docs/01 §4.7, MOB-15b)

Supersedes the open question in the previous entry. The PRD owner decided: `termination` gets
its own event type rather than riding on `lifecycle`'s `state: terminate` (§4.6), because (1)
it's discovered retrospectively at next launch — crash-like, not lifecycle-like; (2) Android's
`ApplicationExitInfo` produces the same shape, so a first-class type is the parity-favoring
choice for the eventual Android port; (3) OOM/thermal/CPU/battery kills are genuinely
actionable and shouldn't be buried among ordinary lifecycle terminations; (4) adding a type is
cheapest now, before a backend consumer exists to migrate.

Schema: `termination_reason` (enum `memory_limit | memory_pressure | cpu | thermal |
low_battery`, required) + optional `time_since_launch_ms`. `unexplained` is dropped entirely,
not just relabeled — the OS gives nothing after SIGKILL, so it's indistinguishable from an
ordinary user/dev termination and is high-volume, zero-diagnostic-value noise. If a real signal
is later found there, adding it back is cheap (it's an additive enum case).

Implemented in `CrashReportMapper.makeTerminationEvent` — `errorType == "termination"` now
routes to a `termination` event when `error["termination_reason"]` is one of the five enum
values, and returns `nil` (dropped, not `crash`) for anything else, including `unexplained`.
`CrashReportMapperTests` covers both branches, parametrized over all nine `KSTerminationReason`
string values KSCrash can actually produce. Real-device verification (an actual OOM/thermal/
CPU/battery kill, not a fixture) is `FEATURES.md` manual checklist item 10 — same host-toolchain
limit as every other crash-adjacent probe in this file.

### 2026-09-01 · `logError` auto-captures call-site location via `#fileID`, never `#file` (docs/01 §4.4, docs/02 MOB-11b)

Real-run finding: pilot data showed the same `"NSError · Produk tidak tersedia"` message 8
times with no way to tell whether that was one unfixed bug or several unrelated call sites
that happen to share a domain/code/message. The existing fingerprint (domain + code +
normalized message) would merge them regardless.

**Decision:** `logError` gains `source_file` / `source_function` / `source_line`, auto-filled
from the call site via Swift default-parameter expressions (`#fileID` / `#function` / `#line`)
— zero developer effort, zero runtime cost (compiler literals). **`#fileID`, never `#file`**:
`#file` is the absolute build-machine path (e.g. `/Users/<name>/dev/proyek/Sources/…`), which
would leak the developer's username and directory layout into the monitoring backend on every
single error event. SEC-05's scrubbing patterns target phone numbers, emails, and JWTs — they
would not catch an arbitrary filesystem path, so this isn't a gap scrubbing closes later; it
has to be the right primitive from the start. `#fileID` gives the safe `Module/File.swift`
short form. This is now written directly into docs/01 §4.4's table, not left as an
implementation detail — the next person implementing this for Android (or a future iOS
rewrite) needs the same warning without having to rediscover it.

**Fingerprint (§6) also changed**, backend-side: `hash(domain + code + normalized message +
source_file + source_function)`. `source_line` is **deliberately excluded** — if it were
included, adding a single line above a call site would shift the line number and fingerprint,
splitting one unfixed bug's history into two apparent issues. `source_file` + `source_function`
are stable under ordinary edits and are exactly what's needed to separate genuinely different
call sites that happen to share a domain/code/message; `source_line` is still sent and
displayed, purely so a person can jump to the code, and is data developers should always
sanity-check isn't stale on a large diff — it just doesn't participate in grouping.

**Implementation:** the default parameters must be declared at *every* public entry point a
host app can call directly (`ManualReporter.logError`, `APM.logError`, `APMInstance.logError`)
and forwarded explicitly at each layer — a default-parameter expression evaluates at its own
declaration's call site, so if an outer wrapper relied on an inner method's default instead of
declaring and forwarding its own, the captured location would silently collapse to wherever
inside the SDK the inner call happens to live, not the app's real call site. Backward
compatible: existing callers (e.g. `VerificationApp`) that don't pass `file`/`function`/`line`
now get them captured for free.

### 2026-09-02 · `crash` payload reshaped to match docs/01 §4.3.1/§4.3.2 exactly, `is_app` added

A spec gap was closed while building the Backoffice: §4.3.1/§4.3.2 now define the exact
per-frame and per-binary-image wire shape, extending MOB-17. The new requirement is `is_app`
on every frame and binary image — `true` for the app's own main binary or an app-owned
framework, `false` for system binaries — set by the SDK at capture time, because only the SDK
can see its own bundle layout; deriving it downstream by name-matching would be fragile and
blind to app-owned frameworks.

**Audit finding, not just `is_app` missing:** `CrashReportMapper` previously re-serialized
KSCrash's raw `threads`/`binary_images` dicts verbatim (`jsonString(threads)`), which never
matched this now-precise contract at all — confirmed against real KSCrash output
(`Example-Reports/*.json` plus the vendored source): addresses are plain decimal numbers, not
the documented hex strings; `binary_images[].name` is the full on-device path, not the
documented basename; `image_addr`/`image_size`/`cpu_type` don't match the documented
`base_addr`/`size`/`arch`; no `file`/`line` keys exist at all (KSCrash instead carries an
unrelated `line_of_code`). Unlike the earlier `termination` gap, this wasn't "which side is
right" — docs/01 is unambiguously authoritative here (the Backoffice is already rendering
against it), so the fix was to bring `CrashReportMapper` in line with the spec, not to flag a
new schema decision.

**How `is_app` is actually computed:** KSCrash reduces every frame's `object_name` to a
basename before we ever see it (`ksfu_lastPathEntry`) — the full path needed to tell "our code"
from "system code" exists *only* on the top-level `binary_images` array, and only there. So
`reshapeBinaryImages` computes `is_app` per image from `image["name"]` (the full path) against
`Bundle.main.bundlePath`, collects the basenames it classified as app-owned, and
`reshapeThreads` looks up each frame's already-basename `object_name` against that set. An
empty `appBundlePath` is explicitly guarded against — `"x".hasPrefix("")` is `true` in Swift,
which would otherwise misclassify every system binary as app-owned.

**Arch string mapping** (`cpu_type`/`cpu_subtype` → `"arm64"`/`"arm64e"`/`"x86_64"`) is
hardcoded rather than imported from Darwin (the Mach-O macros are bitwise expressions the Swift
Clang importer doesn't reliably expose) or pulled from KSCrash's own private
`kscpu_archForCPU` (would need a new module dependency, `RecordingCore`, for six stable,
decades-old constants) — covers every arch this SDK's deployment target can actually report.

**Confirmed matching, no change needed:** docs/01 §4.5.1's breadcrumb snapshot shape
(`timestamp`/`category`/`level`/`message`, JSON-string-encoded) already matches
`Breadcrumb`'s `Codable` output exactly, field names and ISO-8601-with-fractional-seconds
format included — audited, not assumed.
