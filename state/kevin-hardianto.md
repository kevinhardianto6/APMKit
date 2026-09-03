# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** No epic in progress. This session: two envelope fields the Backoffice epic
  exposed gaps for — `user_id_source` (MOB-28 extended, docs/01 §2.2) and `sdk.health` (MOB-27
  extended, docs/01 §2.3).
- **Active feature:** none — implemented, tested, not yet committed.
- **Status:** —
- **Last verify:** `./verify.sh build`/`test`/`budget` → all PASS, 2026-09-02. 248 tests (was
  242 — added 6: 2 `SelfHealthCounters` drop-reason tests, 3 `UserIdentity` source tests, 1
  `EnvelopeFactory` sdk.health test; 4 existing tests got new assertions rather than new tests).

## Next step

1. **Not yet committed** — waiting on the user's go-ahead, per `CONSTITUTION.md`'s "never
   auto-commit."
2. **Pilot ingestion server:** not touched. User said it stores the full envelope verbatim, so
   the two new fields need no server-side schema change to be *accepted* — I have no access to
   that repo from here to verify further, or to check whether the Backoffice's read side
   surfaces them. Flagged, not silently assumed fine.
3. Both new fields are fully covered by `swift test` (pure Swift/UserDefaults logic, no
   platform-specific API) — no new manual-verification checklist item needed, unlike most of
   this repo's other recent additions.

## Parked

- **Android port** — unblocked since Pre-Pilot Hardening closed, not yet scoped. Parity notes:
  `archive/epics/phase-1-2-wrap-up.md`.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

Previous session (commit `20ba1ea`) closed out the MOB-17 `is_app`/crash-payload-reshape work.

| File | What | Why |
|---|---|---|
| `Sources/APMKit/Identity/UserIdentity.swift` | New `UserIdSource` enum (`.host`/`.generated`); new `currentUserIdentity(userDefaults:)` returning `(id, source)` in one pass; `currentUserId` now implemented in terms of it | Reading id and source via two separate calls could straddle a `setUser` landing in between and report a pair that never co-occurred |
| `Sources/APMKit/Core/SDKInfo.swift` | New `SDKHealth` struct (`written`/`sent`/`dropped`/`drop_reasons`); `SDKInfo` gains an optional `health` field | Wire shape for docs/01 §2.3's `sdk.health` |
| `Sources/APMKit/Stability/SelfHealthCounters.swift` | `recordDropped` gains `reason: String = "unknown"`; tracks a `dropReasons: [String: Int]` dict; `Snapshot` carries it | MOB-27 extended — counters need a *why*, not just a count |
| `Sources/APMKit/Storage/DiskQueueEventSink.swift`, `Storage/FileDiskQueue.swift` (×2), `Sync/SyncEngine.swift` | Every existing `recordDropped()` call site now passes a real reason: `write_failure`, `queue_full`, `undecodable`/`decrypt_failure`, `rejected` | Otherwise `drop_reasons` would just be `{"unknown": N}` — the whole point is knowing why |
| `Sources/APMKit/Core/Envelope.swift` | New `userIdSource: UserIdSource?` field/CodingKey (`user_id_source`), default `nil` so existing `Envelope(...)` call sites across the test suite didn't need touching | Wire shape for docs/01 §2.2 |
| `Sources/APMKit/Sync/EnvelopeFactory.swift` | `userId: () -> String?` replaced with `userIdentity: () -> (id: String, source: UserIdSource)`; new `selfHealth: SelfHealthCounters` param; `makeEnvelope` builds `sdk` with a fresh `selfHealth.snapshot()` every call | One closure not two (can't drift apart); health is cumulative runtime state, read fresh, not static context |
| `Tests/.../EnvelopeFactoryTests.swift`, `UserIdentityLeakTests.swift` | Updated to the new `userIdentity:` parameter | Compile fix for the signature change |
| `Tests/.../UserIdentityTests.swift`, `SelfHealthCountersTests.swift`, `EnvelopeFactoryTests.swift`, `EnvelopeTests.swift` | New tests for `currentUserIdentity`, `drop_reasons` accumulation/default, `sdk.health` reflecting a live snapshot, and the full `user_id_source`/`sdk.health` wire shape | Evidence |
| `Tests/.../FileDiskQueueTests.swift`, `SyncEngineTests.swift` | Existing eviction/poison-file/rejected-batch tests gained `dropReasons[...]` assertions | Proves the real call sites use the reasons claimed above, not just that *some* reason exists |
| `CONSTITUTION.md` | New dated decision | Full reasoning |
| `docs/01-Kontrak-Data-API.md`, `docs/02-Mobile-SDK.md` | User's own edits (§2.2/§2.3 new sections, MOB-27/28 extended, plus unrelated §10 User Lookup timeline/breadcrumb-availability note) — pulled and implemented against | Authoritative spec |

_Ground truth: run `git diff --stat` to confirm this table matches reality._
