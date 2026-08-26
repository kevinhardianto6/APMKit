# feat-006 · Identifier & Manual API

- **Status:** ✅ done · closed 2026-08-24 · **Depends on:** feat-001, feat-004
- **Requirements:** `APM.setUser(id:)` takes any free-form string, sent **raw** in
  `envelope.user_id` over TLS, never hashed client-side (hashing to `user_ref` is backend's
  job). Fallback: stable random id persisted per install if never set. Raw `user_id` must
  never leak into breadcrumbs/logs/other fields. Also `APM.logError`. MOB-28, SEC-06.
- **Done when:** raw `user_id` present in envelope, never leaks elsewhere; fallback stable
  per install (tests).

| ✓ | Check | By | Proof |
|:-:|-------|----|-------|
| ✅ | Raw string stored/returned exactly — no hashing, no transformation | Kevin Hardianto | `setUserStoresRawValueExactly`, `acceptsAnyFreeFormString` |
| ✅ | Fallback: stable random id, persisted per install, when never set | Kevin Hardianto | `fallsBackToStableRandomId`, `differentStoresGetDifferentFallbackIds` |
| ✅ | Explicit id takes precedence over fallback, persists across calls | Kevin Hardianto | `explicitIdTakesPrecedenceAndPersists` |
| ✅ | `user_id` fallback is independent of `install_id` (separate concepts, separate keys) | Kevin Hardianto | `installIdAndUserIdFallbackAreIndependent` |
| ✅ | `EnvelopeFactory` threads a `UserIdentity`-backed `userId` closure through unchanged | Kevin Hardianto | `EnvelopeFactoryTests.threadsUserIdentityUserIdThrough` |
| ✅ | `APM.logError` → `error` event, `handled` always `true`, custom context included and capped (20 keys / 256 chars, docs/01 §4.4) | Kevin Hardianto | `ManualReporterTests` (3 tests) |
| ✅ | **Raw `user_id` never leaks into any queued event's attrs/ctx, or into the actual disk-queue file bytes**, across a real network request AND a manual `logError` call in the same session — and DOES correctly reach the one legitimate place (the envelope) | Kevin Hardianto | `UserIdentityLeakTests.userIdNeverLeaksIntoQueuedEventsOrDiskBytes` (real pipeline, real disk bytes read back) |

10 tests total (107 cumulative), `./verify.sh all` → `HARNESS_VERIFY: PASS (all)` (2026-08-24),
re-run 3× clean. Confirmed via `git stash -u` diff that the jump from feat-005's 97 to
feat-006's 107 is a clean net +10 — no tests silently dropped or merged (a typo in the
original review summary said "110 → 107", which was wrong; corrected here).

**Decisions**
- **`user_id` never touches the disk queue at all — a stronger property than "it's scrubbed."**
  `FileDiskQueue` only ever stores individual `Event`s; `Envelope` (the only place `user_id`
  lives) is assembled purely in-memory by `EnvelopeFactory` at upload time from an
  already-queued batch. There is no code path where `user_id` could reach a disk-written
  `Event` even accidentally — not "the Scrubber catches it if it shows up," but "it structurally
  cannot show up there." The leak test proves this on real disk bytes rather than asserting it
  from the architecture alone, per the user's explicit request for a test "like the disk-level
  scrubbing one."
- **`UserIdentity` mirrors `InstallIdentity`'s exact style** (enum, static functions over
  injectable `UserDefaults`) for consistency, but uses a **separate** UserDefaults key from
  `install_id` — these answer different questions (device install vs. user identity) even
  though both fall back to a stable-per-install random value. Verified independence directly
  (`installIdAndUserIdFallbackAreIndependent`).
- **No validation or hashing of any kind on `setUser(id:)`.** Per the user's explicit reminder
  and docs/01 §2.1/SEC-06: the SDK must accept phone numbers, emails, or arbitrary text
  without inspecting them — hashing to `user_ref` is exclusively the backend's job. Tested with
  phone-shaped, email-shaped, and arbitrary strings, including one with an emoji, to make the
  "no validation at all" claim concrete rather than assumed.
- **`APM.logError` takes an explicit `sink`/`sessionManager`, not zero arguments.** Matches
  `instrumentedSession()`'s existing dependency style — there is still no composition root
  (no `APM.start()`) to hold ambient state for a truly zero-argument call. `ManualReporter` is
  the reusable class underneath; `APM.logError` is a thin static convenience over it.
- **`context: [String: String]` truncation order is unspecified.** Swift `Dictionary` has no
  defined iteration order, so which 20 of >20 keys survive `.prefix(20)` isn't deterministic.
  docs/01 §4.4 doesn't specify which keys should be kept when over the limit, only that the
  cap exists — flagging this as a minor spec gap; not worth blocking on, since exceeding 20
  custom keys should be rare in practice.

**Blockers** — none.

**Files added:** `Sources/APMKit/Identity/{UserIdentity,ManualReporter}.swift`.
`Tests/APMKitTests/Identity/{UserIdentityTests,ManualReporterTests}.swift`,
`Tests/APMKitTests/UserIdentityLeakTests.swift`.
**Files amended:** `Sources/APMKit/APMKit.swift` (`APM.setUser(id:)`, `APM.logError(...)`);
`Sources/APMKit/Sync/EnvelopeFactory.swift` (`userId` default: `{ nil }` →
`{ UserIdentity.currentUserId() }`); `Tests/APMKitTests/Sync/EnvelopeFactoryTests.swift`
(updated the now-stale "defaults to nil" test).
