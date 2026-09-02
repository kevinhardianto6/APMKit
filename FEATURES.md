# Features

> Scope backbone, grouped by epic (one epic = one PRD = one ID prefix).
> Status: 🟡 not started · 🔵 in progress · ✅ done · 🔴 blocked · 🟠 needs verification
> **One feature is active at a time per person** (see `state/<name>.md`) — the backlog may span epics.
> `By` = who actually did the work, from `git config user.name` on the machine that ran it.
> Completed feature detail → `archive/features/`. Completed *epics* → `archive/epics/`, listed under Shipped.

| Epic | Progress | Active / open |
|------|:--------:|---------------|
| _(no epic in progress — Pre-Pilot Hardening shipped 2026-08-31, see Shipped below)_ | — | — |

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
| 1 | Integrity probes: `isRooted()`'s real file/symlink/sandbox-write checks, `isDevMode()`'s provisioning-profile/receipt lookup, `isEmulator()`'s `true` branch (only reachable compiled for Simulator). Only the pure `JailbreakVerdict`/`DevModeVerdict` combination logic is proven by `swift test`. **Update 2026-09-01:** pilot ingestion server's real traffic showed every clean Simulator session reporting `is_rooted = true` — fixed (`JailbreakVerdict.sandboxWriteSignal` discards the sandbox-write probe's raw result on Simulator, since it structurally always succeeds there; device logic untouched). The fix's pure mapping is unit-tested; whether `is_rooted` actually reads `false` end-to-end on a real Simulator still needs this same manual verification. | feat-008 | ☐ not verified |
| 2 | OS-level automatic breadcrumb firing: real `UIApplication` lifecycle notifications and real `NWPathMonitor` connectivity transitions actually invoking `AutomaticBreadcrumbSource`'s `recordLifecycle`/`recordConnectivity`. Only the mapping logic is proven by `swift test`. | feat-007 | ☐ not verified |
| 3 | SEC-07's `FileProtectionType`: protection level and backup-exclusion flag have no observable effect on the macOS test host; needs a real-device/simulator file-attribute check. | feat-002 | ☐ not verified |
| 4 | docs/02 §7 Fase 1 scenarios not covered by any automated test: disk full (real `ENOSPC`, not just the SDK's own size cap), and force-quit specifically *during* an in-flight upload (offline buffering itself is tested; the exact "killed mid-HTTP-request" timing is not). | feat-002, feat-005 | ☐ not verified |
| 5 | Performance budget (docs/02 §5) — the part that isn't CI-measurable: CPU ≤2% average, memory ≤8MB resident, and cold-start overhead ≤30ms p95, each needing real-device profiling under realistic load. Binary size and main-thread I/O structural checks *are* now CI-gated (feat-012). **Update 2026-08-31 (feat-016):** the "no app to measure against" blocker is gone — `VerificationApp` exists and cold-start is now genuinely measurable; 8 real Simulator cold launches measured 22.4–40.6ms (2/8 over budget). Simulator timing is not a substitute for real-device profiling (different hardware/scheduler) — still needs an actual device run. | Phase 1 (all); split by feat-012; unblocked by feat-016 | ☐ not verified (Simulator numbers recorded, real device still needed) |
| 6 | A forced crash captured by real KSCrash on iOS Simulator/device, appearing correctly after relaunch (feat-009's actual "Done when" criterion). | feat-009 | ☑ verified 2026-08-28 — `IOSCrashHarnessTests.phase1_forceCrash`/`phase2_readBackAfterRelaunch`, run via `xcodebuild test` against a booted iOS 18.0 Simulator; re-runnable any time per that file's header comment. **Caveat added 2026-09-02:** `CrashReportMapper`'s `threads`/`binary_images` reshaping changed materially since this verification (item 11) — this item's own assertions only check `binary_images` is non-empty, so it wasn't broken, but it also doesn't prove the *new* shape is correct on a real device. Re-running it is still good evidence the pipeline as a whole works; it just isn't item 11's evidence. |
| 7 | A real >2s main-thread block detected live by KSCrash's `Watchdog` monitor + `HangDetector`, without the detector itself blocking or hanging (MOB-18's actual "Done when"). | feat-010 | ☑ verified 2026-08-29 — `IOSCrashHarnessTests.phase3_hangDetection`, same Simulator/invocation pattern as item 6. |
| 8 | The `.github/workflows/ci.yml` GitHub Actions workflow (feat-012) actually fires and gates a real PR — unverified in this environment because this repo has no git remote configured here. Its YAML is syntax-valid and it runs the same `./verify.sh all` already verified to pass locally. | feat-012 | ☐ not verified |
| 9 | True cross-app-relaunch Keychain persistence for SEC-08's encryption key (does the queue encrypted by one app launch still decrypt after the app is quit and relaunched — not via `xcodebuild test`, which resets Keychain state between invocations regardless of app identity). | feat-014 | ☑ verified 2026-08-31 (feat-016) — `VerificationApp` installed via `simctl`, launched, 2 real encrypted events written and read back; `simctl terminate` (confirmed via `launchctl list`) then `simctl launch` again as a genuinely new process (PID changed); second process's independent `FileDiskQueue` read-back decoded all 5 accumulated events using the Keychain-persisted key. Required fixing the verification app's code signing (`CODE_SIGNING_ALLOWED = NO` → ad-hoc `"-"`) — an unsigned app's Keychain round-trip was unreliable; see `archive/features/feat-016.md`. |
| 10 | A real OS-triggered termination (OOM/thermal/CPU/battery kill, not a simulated fixture) actually surfacing as KSCrash's Termination-monitor report on next launch, with `termination_reason` carrying one of the five resource enum values, and correctly mapped to a `termination` event (docs/01 §4.7, docs/02 MOB-15b, added 2026-09-01) rather than `crash`. `CrashReportMapperTests` proves the mapping logic against fixture dictionaries only — no automated test can force a real memory/thermal/CPU/battery-critical kill. | MOB-15b, 2026-09-01 real-run finding | ☐ not verified |
| 11 | The reshaped `threads`/`binary_images` wire payload (docs/01 §4.3.1/§4.3.2, `is_app`, hex address strings, `arch`) against a *real* KSCrash report — `CrashReportMapperTests` proves the transform logic against fixtures built from `Example-Reports/*.json`'s documented shape, not a live report. In particular: does real KSCrash actually bridge `image_addr`/`object_addr`/`image_size` as `Int` (vs. `Double`/`NSNumber` edge cases `hexAddress`'s two-branch cast might miss), and does a real device's `Bundle.main.bundlePath` prefix-match its own `binary_images[].name` the way assumed. | MOB-17 extension, 2026-09-02 Backoffice spec gap | ☐ not verified |

Items 1–4 (feat-002/007/008, Phase 1) remain unverified as of 2026-08-31 — feat-009/010 added
their own device-only checks (6, 7) but did not re-visit these; feat-012 narrowed item 5's scope,
feat-016 unblocked it (Simulator numbers recorded) but real-device profiling is still needed.
feat-016 also verified item 9 for real via `VerificationApp`. Item 10 added 2026-09-01 alongside
the `termination` event type. Item 11 added 2026-09-02 alongside the `is_app`/reshaped crash
payload work. Still the running punch list before the pilot ships.

## Shipped

Completed epics, rotated to `archive/epics/`. One line each.

- **APM Kit iOS SDK** (2026-08-24 → 2026-08-29, 10/10 features) — Phase 1 (network
  observability) + Phase 2 (crash reporting, stability, remote control). Full detail:
  [archive/epics/apmkit-ios-sdk.md](archive/epics/apmkit-ios-sdk.md); requirement coverage +
  Android parity notes: [archive/epics/phase-1-2-wrap-up.md](archive/epics/phase-1-2-wrap-up.md).
- **Pre-Pilot Hardening** (2026-08-29 → 2026-08-31, 6/6 features) — TLS floor + fail-closed,
  CI-enforced performance budget, CocoaPods/semver distribution, at-rest queue encryption,
  optional certificate pinning, composition root (`APM.start`). Full detail:
  [archive/epics/pre-pilot-hardening.md](archive/epics/pre-pilot-hardening.md).
