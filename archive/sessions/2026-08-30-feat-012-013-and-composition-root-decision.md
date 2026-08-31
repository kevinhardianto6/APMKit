# Session — 2026-08-30 — feat-012, feat-013, feat-016 filed

## Changes

| File | Change | Why |
|------|--------|-----|
| `scripts/size-budget/` (Package.swift, `Sources/Baseline`, `Sources/WithSDK`) | Added | feat-012 — throwaway SPM package to measure APMKit's real linked-binary size delta |
| `scripts/check-binary-size-budget.sh` | Added | feat-012 — builds both probes, gzip-diffs them, fails over 1.5MB |
| `verify.sh` | +`budget`, +`podspec` modes, both included in `all` | feat-012, feat-013 |
| `AGENTS.md` | Verification section documents `budget`/`podspec`/`all` | feat-012, feat-013 |
| `Tests/APMKitTests/Sync/MainThreadIOStructuralTests.swift` | Added (3 tests) | feat-012 — dynamic proof SyncEngine's automatic triggers don't block |
| `.github/workflows/ci.yml` | Added | feat-012 — minimal PR-triggered `verify.sh all` |
| `APMKit.podspec` | Added | feat-013, MOB-23 — depends on `KSCrash/Recording` matching SPM |
| `Sources/APMKit/APMKit.swift`, `Crash/{CrashReporter,CrashReportSource,CrashUserInfoStore}.swift`, `Stability/HangObserving.swift` | `import KSCrashRecording` → conditional on `canImport` | Real CocoaPods/SPM module-name mismatch found via `pod lib lint`, not assumed |
| `VERSIONING.md` | Added | feat-013, MOB-24 — semver policy, two-manifest-sync risk, integration-friction writeup |
| `Tests/APMKitTests/VersioningTests.swift` | Added | Locks `SDKInfo`/podspec version parity |
| `FEATURES.md` | feat-012 → ✅, feat-013 → ✅, feat-016 filed (Composition Root) | Features closed; new feature added at user's direction |
| `archive/features/feat-012.md`, `archive/features/feat-013.md` | Added — full detail | Rotation |

## What went right / notable decisions

- **feat-012 cold-start judgment call** — user asked explicitly for reasoning, not just a
  yes/no. Landed on treating cold-start like CPU/memory (manual checklist, not CI-gated):
  no sample host app exists to attach a meaningful measurement to, and CI noise would swamp a
  30ms budget regardless. User confirmed reason 1 (no host app) was decisive.
- **feat-012 main-thread-I/O test is dynamic, not a code read** — injected artificial 0.5s
  latency into disk/network, asserted `SyncEngine`'s automatic triggers still return in <50ms.
  A real regression guard: would fail if `workQueue.async` became `.sync`.
- **feat-013 SPM external-resolution proof** — a real bare git clone, tagged, consumed via
  `file://` URL from a separate package, not a local path dependency (which every prior
  scratchpad harness used and doesn't exercise the same code path a real consumer does).
- **feat-013 CocoaPods finding** — `pod lib lint` genuinely failed on the first attempt
  (`Unable to resolve module dependency: 'KSCrashRecording'`), root-caused by inspecting the
  actual generated module maps (CocoaPods' KSCrash pod exposes one umbrella module `KSCrash`,
  not per-subspec ones like SPM), fixed with conditional imports. Caught by actually running
  the tool, not by reading KSCrash's podspec structure and assuming it would work.
- **feat-013 flagged, not fixed: no composition root.** User's response: don't defer it, file
  it as feat-016, scheduled before the pilot (after feat-014/015, since it needs to assemble
  what those build, including feat-015's pinning config). Reasoning tied explicitly to two
  prior "make forgetting structurally impossible" fixes (feat-005 anti-loop, feat-009's
  pending-report drain) — same fix shape, applied to the whole integration.

## Verification

185 tests at feat-011's close → 186 at feat-013's close. `./verify.sh all` →
`HARNESS_VERIFY: PASS (all)` throughout (now five sub-checks: build/test/lint/budget/podspec).

Commits this session: `dea5747` (feat-011 + feat-012), `a609201` (feat-013). feat-016 filed in
`FEATURES.md` but not yet committed as of this rotation — see current
`state/kevin-hardianto.md`.
