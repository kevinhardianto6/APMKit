# feat-008 · Device Integrity

- **Status:** ✅ done · closed 2026-08-28 · **Depends on:** feat-001
- **Requirements:** snapshot once per session into `envelope.integrity`: `is_emulator`
  (`TARGET_OS_SIMULATOR`/env), `is_rooted` (jailbreak file checks + sandbox-write test +
  suspicious symlinks), `is_dev_mode` (debugger via `sysctl` `P_TRACED` + non-App-Store build
  via `embedded.mobileprovision`/TestFlight `sandboxReceipt`), `debugger_attached`. Heuristic
  only — no privileged APIs (no IMEI). MOB-29/30/31.
- **Done when:** flags correct on real device + simulator (manual verification required —
  simulator-only automation can't fully prove real-device jailbreak/dev-mode detection).

| ✓ | Check | By | Proof |
|:-:|-------|----|-------|
| ✅ | `isRooted`/`isDevMode` combination logic (any signal → true; no signal → false), portable, fully unit-tested | Kevin Hardianto | `IntegrityVerdictsTests` (9 tests) |
| ✅ | `debugger_attached` via `sysctl` `P_TRACED` bit-check logic, incl. ignoring unrelated flag bits | Kevin Hardianto | `DeviceIntegrityDetectorTests` (3 debugger tests) |
| ✅ | `isEmulator()` compiles/runs correctly via `#if targetEnvironment(simulator)` — false branch only, see Decisions | Kevin Hardianto | `isEmulatorRunsWithoutCrashing` |
| ✅ | `isRooted()`/`isDevMode()` non-iOS fallback compiles and returns `false` — fallback only, see Decisions | Kevin Hardianto | `rootedAndDevModeFallbackOnHost` |
| ✅ | `snapshot()` wires all four probes into one `IntegritySnapshot` | Kevin Hardianto | `snapshotWiresAllFourProbes` |
| ✅ | Snapshot computed once per session, cached, invalidated exactly on session rotation (long background), NOT invalidated by a short background | Kevin Hardianto | `SessionManagerTests`: `integritySnapshotComputedOnce`, `integritySnapshotInvalidatedOnSessionRotation`, `integritySnapshotSurvivesShortBackground` |
| ✅ | `EnvelopeFactory`'s default `integrity` reads the session-cached snapshot, not `.unset` | Kevin Hardianto | `EnvelopeFactoryTests.defaultIntegrityUsesSessionCachedSnapshot` |

14 tests total (131 cumulative), `./verify.sh all` → `HARNESS_VERIFY: PASS (all)` (2026-08-27),
re-run 3× clean.

**Review history:** user approved outright — specifically confirmed the MOB-31
two-independent-booleans reading was correct ("your reading of MOB-31 was correct, not
mine") and endorsed putting the once-per-session cache in `SessionManager` rather than a
separate component ("one code path owns both rotation and invalidation, so they can't
drift").

**Decisions**
- **Design split for honest testability: pure verdict-combination logic vs. real OS probes.**
  `JailbreakVerdict.isRooted`/`DevModeVerdict.isDevMode` are portable pure functions ("any
  signal true → true") with zero platform dependency, fully unit-tested with truth tables.
  The real probes that feed them — suspicious-file checks, the sandbox-write attempt,
  symlink checks, provisioning-profile/receipt lookup — are `#if os(iOS)`-gated in
  `DeviceIntegrityDetector` and return `false` unconditionally on other platforms. This is the
  same shape as feat-002's `FileProtectionType` gap and feat-007's `UIApplication` gap: the
  **combination logic** is proven; the **real-world detection** genuinely cannot be exercised
  by `swift test` on macOS and needs a real device/simulator — user explicitly confirmed this
  goes on the manual pilot-verification list, not something to fake in tests.
- **`isEmulator()` is correct by construction but its `true` branch is unreachable in this
  test environment.** `#if targetEnvironment(simulator)` is a compile-time check — a macOS
  host build for `swift test` is never compiled for iOS Simulator, so the function can only
  ever return `false` here, proving the false branch is wired correctly but nothing about the
  true branch. Only `xcodebuild test -destination 'platform=iOS Simulator,...'` (or a real
  Simulator run) can exercise it.
- **`debugger_attached`'s `sysctl`/`P_TRACED` mechanism is genuinely portable** (Darwin's BSD-
  derived `sysctl` exists on macOS too) — unlike the jailbreak/dev-mode probes, this one's
  real logic (not just a fallback) is exercised by `swift test`, via an injectable
  `processFlags` closure so tests don't depend on whether the test runner itself happens to be
  debugged.
- **"Once per session" caching lives in `SessionManager`, not `DeviceIntegrityDetector`.**
  `SessionManager` already owns session lifecycle/rotation (`sessionId`, `seqCounter`); adding
  the integrity cache there means invalidation is automatically correct by construction
  (rotator and invalidator are the same code path in `appWillEnterForeground`) rather than
  needing two components to agree on when a "new session" starts. `EnvelopeFactory`'s
  `integrity` parameter became `(() -> IntegritySnapshot)?` (was a non-optional closure with
  a `{ .unset }` default) since Swift can't reference one init parameter (`sessionManager`)
  inside another parameter's default-value expression — the real default is resolved inside
  the initializer body instead. **User confirmed this was the right call.**
- **Reading of MOB-31's "debugger via sysctl P_TRACED + non-App-Store build via
  embedded.mobileprovision/TestFlight sandboxReceipt"**: implemented as two independent
  booleans (`debuggerAttached` = sysctl check only; `isDevMode` = non-App-Store-build check
  only), matching the envelope schema's four separate fields, rather than `is_dev_mode` being
  defined as `debuggerAttached OR nonAppStoreBuild`. **User confirmed correct** and updated
  `docs/02-Mobile-SDK.md` MOB-31 to say exactly this explicitly ("dua boolean independen ...
  bukan digabung dengan OR"), with the rationale that a TestFlight build a QA tester runs
  without an attached debugger is a materially different signal than an active debugging
  session, and OR-ing them would make the schema's separate `debugger_attached` field
  redundant.
- **No attestation, no privileged APIs — matches the user's explicit constraint.** No
  App Attest/DeviceCheck (post-v1 per docs/00 §11), no IMEI/serial — nothing here needs a
  permission prompt or restricted entitlement.

**Blockers** — none.

**Files added:** `Sources/APMKit/Integrity/{IntegrityVerdicts,DeviceIntegrityDetector}.swift`.
`Tests/APMKitTests/Integrity/{IntegrityVerdictsTests,DeviceIntegrityDetectorTests}.swift`.
**Files amended:** `Sources/APMKit/Core/SessionManager.swift` (`currentIntegritySnapshot()`
caching); `Sources/APMKit/Sync/EnvelopeFactory.swift` (`integrity` default now session-cached,
not `.unset`); `Tests/APMKitTests/Core/SessionManagerTests.swift`,
`Tests/APMKitTests/Sync/EnvelopeFactoryTests.swift` (new tests added).
