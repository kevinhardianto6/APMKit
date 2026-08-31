# Session — 2026-08-31 — feat-015, feat-016, epic shipped

Continues from `archive/sessions/2026-08-30-feat-012-013-and-composition-root-decision.md`
(feat-014 close). This session closed the Pre-Pilot Hardening epic (6/6): feat-015 (Optional
Certificate Pinning) and feat-016 (Composition Root + internal verification app).

## feat-015 — Optional Certificate Pinning (SEC-11)

Committed as `629634c`. Full detail: `archive/features/feat-015.md`. Highlights: backup pin
structurally required via a failable init; kill switch checked on every TLS challenge, not
cached at setup; real TLS test infrastructure built from scratch (hand-rolled ASN.1 DER
self-signed cert generation + a `Network.framework` TLS listener) since nothing in this repo
could drive a genuine handshake before this feature. Two test-infra bugs found and fixed along
the way: a mock-server request race, and a Keychain-contention flake this session's own new
test infra introduced into feat-014's pre-existing `DiskQueueKeyStoreTests` (fixed with a
shared `KeychainTestLock`).

## feat-016 — Composition Root (`APM.start`) + internal verification app

Full detail: `archive/features/feat-016.md`. Spiked the `.xcodeproj` question first, per the
user's explicit instruction to stop and report if it looked disproportionate — it worked on the
first real attempt (hand-written pbxproj, no scaffolding tool available in this environment).
Built `APM.start(configuration:)` as one call assembling the whole pipeline; extended
`AutomaticBreadcrumbSource` with hooks instead of a second competing observer set for the
background/connectivity triggers.

Found and fixed one real gotcha in the verification app itself: `CODE_SIGNING_ALLOWED = NO`
(the simplest thing that builds) breaks real Keychain persistence — switched to ad-hoc signing.
This is what let checklist item 9 (Keychain persistence across a real relaunch) get **genuinely
verified for the first time** in this project: 2 events written pre-terminate, `simctl
terminate` (confirmed via `launchctl list`) + `simctl launch` as a verified new process (PID
changed), 5 events (old + new) all decrypted successfully by the second process's independent
Keychain-backed key lookup.

Checklist item 5 (cold-start) was **unblocked, not closed** — measured 8 real Simulator cold
launches (22.4–40.6ms, 2/8 over the 30ms budget) but was explicit in both the archive and
`FEATURES.md` that Simulator timing isn't a substitute for real-device profiling.

The timed-integration "Done when" was handled honestly rather than fabricated: wrote
`docs/03-Integration-Guide.md` first, reset the verification app to a blank pre-integration
state, then re-integrated following only that doc. Reported the mechanical AI edit time (45s)
as explicitly NOT a valid proxy for a human's 30-minute budget, and gave the real evidence
instead — one required call, first-attempt build success, real device confirmation.

Also found and fixed a test-isolation bug in the process of writing feat-016's own tests:
`APM.start`'s `RemoteConfigStore` defaulting to `UserDefaults.standard` let one test's kill-
switch state leak into every other `APM.start()` call in the same `swift test` process. Fixed
by adding an injectable `Configuration.remoteConfigUserDefaults`.

## Epic closed

Pre-Pilot Hardening: 6/6 features, 2026-08-29 → 2026-08-31. Rotated to
`archive/epics/pre-pilot-hardening.md`. Android port is unblocked (see that epic's own
wrap-up + `archive/epics/phase-1-2-wrap-up.md` → "What an Android port would need for parity")
but not scoped into `FEATURES.md` yet — that's the next real decision, not assumed here.

## Changes this session

| File | Change | Why |
|------|--------|-----|
| feat-015 files | see `archive/features/feat-015.md` | committed `629634c` |
| `Sources/APMKit/Composition/APMConfiguration.swift` | new: `APM.Configuration` | feat-016 |
| `Sources/APMKit/Composition/APMInstance.swift` | new: returned by `start()` | feat-016 |
| `Sources/APMKit/Composition/APMStart.swift` | new: `APM.start(configuration:)` | feat-016 |
| `Sources/APMKit/Composition/EphemeralInMemoryDiskQueue.swift` | new: never-throw fallback | feat-016 |
| `Sources/APMKit/Breadcrumbs/AutomaticBreadcrumbSource.swift` | +3 hooks, nil default | feat-016 |
| `Sources/APMKit/APMKit.swift` | `fetchRemoteConfig` gained `pinning:` | feat-016 |
| `Tests/APMKitTests/Composition/APMStartTests.swift` | new: real end-to-end pipeline tests | feat-016 |
| `Tests/APMKitTests/Composition/EphemeralInMemoryDiskQueueTests.swift` | new | feat-016 |
| `Tests/APMKitTests/Breadcrumbs/AutomaticBreadcrumbSourceTests.swift` | +2 tests for new hooks | feat-016 |
| `docs/03-Integration-Guide.md` | new: the doc the timed integration followed | feat-016 |
| `VerificationApp/` | new: hand-written `.xcodeproj` + minimal SwiftUI app | feat-016 |
| `FEATURES.md` | feat-016 ✅, epic rotated to archive, checklist items 5/9 updated | feat-016 close, epic close |
| `archive/features/feat-016.md` | new | feat-016 close |
| `archive/epics/pre-pilot-hardening.md` | new | epic close |

225 tests (was 196 at session start). `./verify.sh build`/`test`/`budget` all
`HARNESS_VERIFY: PASS`, `test` re-run 8×+ clean at each checkpoint.

**Not yet committed as of session end** — feat-016's changes above (feat-015 already
committed as `629634c`).
