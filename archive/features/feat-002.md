# feat-002 · Disk Queue

- **Status:** ✅ done · closed 2026-08-24 · **Depends on:** feat-001
- **Requirements:** local-first persistence behind a protocol; atomic write; survives process
  kill/force-quit/restart; cap ~20MB or ~5000 events, FIFO eviction. MOB-04/05/06. Also folds
  in SEC-07 (data-at-rest file protection + backup exclusion on the queue directory) — see
  Decisions below for why that wasn't in the original F-mapping.
- **Done when:** survives a simulated restart; FIFO-evicts when full (tests).

| ✓ | Check | By | Proof |
|:-:|-------|----|-------|
| ✅ | Atomic write (`Data.write(options: .atomic)`, temp+rename) | Kevin Hardianto | `strayArtifactIsIgnored` — a torn write's temp artifact never surfaces |
| ✅ | Survives simulated process kill / restart | Kevin Hardianto | `survivesSimulatedRestart`, `sequenceRecoveryAvoidsCollisionAfterRestart` |
| ✅ | FIFO order preserved | Kevin Hardianto | `enqueueThenPeekIsFIFO`, `removeDeletesOnlyGivenIds` |
| ✅ | FIFO eviction at event-count cap (~5000 default) | Kevin Hardianto | `evictsOldestWhenCountCapExceeded` |
| ✅ | FIFO eviction at byte-size cap (~20MB default) | Kevin Hardianto | `evictsOldestWhenByteCapExceeded` |
| ✅ | SEC-07: file protection + backup exclusion on queue dir | Kevin Hardianto | `FileDiskQueue.applyDataProtection` (not independently unit-tested — `FileProtectionType` has no observable effect on macOS host; needs a real-device/simulator check later) |

8 tests total (23 cumulative with feat-001), `./verify.sh all` → `HARNESS_VERIFY: PASS (all)` (2026-08-24).
Committed as `43ef425` — `feat-002: Disk Queue`.

**Decisions**
- SEC-07 wasn't mapped to any F-number in the original build order despite governing this
  exact file. Per user direction, folded into feat-002 rather than tracked as a separate
  future row — see reasoning inline in `FileDiskQueue.swift`.
- One-file-per-event on disk (not one append-only log file). Chosen over a log file because
  it makes FIFO eviction, partial-write safety, and selective removal-by-id all fall out of
  filesystem operations (`removeItem`, directory listing + sort) instead of needing a custom
  log format with compaction. Filename encodes a zero-padded monotonic sequence + event_id,
  so directory listing sorted by name *is* FIFO order.
- `enqueue`/`peek`/`remove`/`count`/`sizeInBytes` are synchronous and serialized on a private
  `DispatchQueue` — `enqueue` blocks the calling thread until the event is durably on disk.
  This is intentional: the "write local first" principle requires the write to have
  *completed* before any subsequent network call, so callers (feat-003 onward) must invoke
  this off the main thread, not treat it as fire-and-forget.
- SEC-07's `FileProtectionType` API is iOS-only (`#if os(iOS)`), following the same
  host-toolchain-compilation pattern as feat-001's `DeviceInfo`. Backup exclusion
  (`isExcludedFromBackup`) is cross-platform and applied unconditionally.

**Blockers** — none.

**Files added:** `Sources/APMKit/Storage/{DiskQueue,FileDiskQueue}.swift`,
`Tests/APMKitTests/Storage/FileDiskQueueTests.swift`.
