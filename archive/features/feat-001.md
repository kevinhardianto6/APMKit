# feat-001 · Core & Envelope

- **Status:** ✅ done · closed 2026-08-24 · **Depends on:** —
- **Requirements:** event model, envelope, device context, session lifecycle (session_id
  resets after >30s background), install_id — schema per `docs/01-Kontrak-Data-API.md` §2–5.
- **Done when:** constructs + serializes the exact envelope JSON; unit tests assert on JSON
  shape (field names, types, required vs optional).

| ✓ | Check | By | Proof |
|:-:|-------|----|-------|
| ✅ | Envelope encodes to the exact shape in `01` §2 | Kevin Hardianto | `EnvelopeTests.encodesExactShape`, `nilUserIdRoundTrips`, `roundTrips` |
| ✅ | Event encodes to the exact shape in `01` §3 | Kevin Hardianto | `EventTests.encodesExactShape`, `ctxOptionalFieldsDecodeAsNil`, `attributeValueRoundTrips` |
| ✅ | session_id resets after >30s background | Kevin Hardianto | `SessionManagerTests.longBackgroundRotatesSession`, `shortBackgroundKeepsSameSession`, `seqResetsOnRotation` |
| ✅ | install_id persists across launches (simulated) | Kevin Hardianto | `InstallIdentityTests.persistsAcrossCalls`, `differentStoresGetDifferentIds` |

15 tests total, `./verify.sh all` → `HARNESS_VERIFY: PASS (all)` (2026-08-24).
Committed as `5b3d58c` — `feat-001: Core & Envelope`.

**Decisions**
- `IntegritySnapshot.unset` (all-`false`) is the feat-001 stub; real detection lands in
  feat-008. Documented in the type's doc comment so it isn't mistaken for a real signal.
- `DeviceInfo.current()` gates on `#if canImport(UIKit)` so the package still compiles/tests
  on the host macOS toolchain (`swift test`, no simulator) — see `CONSTITUTION.md` platform
  invariants. The non-UIKit branch is test-scaffolding only; the SDK always ships on iOS.

**Blockers** — none.

**Files added:** `Sources/APMKit/Core/{AttributeValue,SDKInfo,DeviceInfo,IntegritySnapshot,
EventContext,ISO8601Formatting,Event,Envelope,InstallIdentity,SessionManager}.swift`,
`Tests/APMKitTests/Core/{EnvelopeTests,EventTests,SessionManagerTests,InstallIdentityTests}.swift`.
Removed the placeholder `Tests/APMKitTests/APMKitTests.swift` scaffold test.
