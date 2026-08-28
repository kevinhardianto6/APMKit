# feat-007 · Breadcrumbs

- **Status:** ✅ done · closed 2026-08-27 · **Depends on:** feat-004, feat-006
- **Requirements:** `APM.breadcrumb(_:category:)` + automatic (screen/lifecycle/connectivity);
  ring buffer of last 100 attached to each error event. MOB-11/12/13.
- **Done when:** ring buffer attaches to errors; auto-crumbs fire (tests).

| ✓ | Check | By | Proof |
|:-:|-------|----|-------|
| ✅ | Ring buffer keeps last 100, FIFO eviction, insertion order preserved | Kevin Hardianto | `BreadcrumbRingBufferTests` (4 tests) |
| ✅ | `logError` attaches a JSON snapshot of the ring buffer to the `error` event | Kevin Hardianto | `logErrorAttachesBreadcrumbSnapshot`, `logErrorWithNoBreadcrumbsAttachesEmptyArray` |
| ✅ | Lifecycle/connectivity mapping logic (what a real OS callback would trigger) | Kevin Hardianto | `AutomaticBreadcrumbSourceTests` (3 tests) — see Decisions for what this does and doesn't prove |
| ✅ | **A phone number in a real breadcrumb message never reaches disk** — real `APM.breadcrumb`-shaped data through the real `Scrubber` → `FileDiskQueue` pipeline, checked against actual queue-file bytes | Kevin Hardianto | `BreadcrumbLeakTests.phoneNumberInBreadcrumbNeverReachesDiskUnredacted` |

10 tests total (117 cumulative), `./verify.sh all` → `HARNESS_VERIFY: PASS (all)` (2026-08-24),
re-run 3× clean.

**Decisions**
- **No `UIViewController` swizzling for automatic screen-transition breadcrumbs — user
  decision, asked directly (AskUserQuestion).** MOB-12 says "automatic screen transitions,"
  but the only way to get that with zero integration effort on iOS is swizzling
  `viewDidAppear` (or similar), which is invasive, carries real crash/undefined-behavior risk,
  and can silently conflict with another SDK doing the same thing — the user specifically
  named Firebase's own swizzling as a live risk in their app, and any resulting crash would be
  blamed on this SDK regardless of whose swizzle broke it (`CONSTITUTION.md` rule #1; docs/00
  G4 adoption risk). Implemented instead: `APM.recordScreen(_:)` as the primitive
  (host-invoked), plus two opt-in convenience layers so it isn't per-screen boilerplate —
  `APMTrackedViewController` (subclass instead of `UIViewController`, defaults the screen name
  to the type name) and `View.apmScreen(_:)` (SwiftUI `.onAppear` wrapper).
  **2026-08-27: user said docs/02 was updated on their side, but it wasn't actually reflected
  in this repo's `docs/02-Mobile-SDK.md` at the time** — checked directly (`grep` for
  "swizzl"/"ActivityLifecycleCallbacks"/"host-invoked", MOB-12's line unchanged), flagged
  back rather than silently treating the doc as updated. **2026-08-28: now confirmed landed**
  — `docs/02-Mobile-SDK.md` MOB-12 was updated exactly as described: split into
  genuinely-automatic sources (lifecycle, connectivity) vs. host-invoked screen tracking, with
  the no-swizzling rationale recorded verbatim (naming Firebase's own `viewDidAppear`
  swizzling as the concrete conflict risk) and an explicit Android parity note that
  `ActivityLifecycleCallbacks` can keep screen tracking automatic there, with only the
  breadcrumb *output* (category `navigation`) required to match across platforms, not the
  trigger mechanism. No code change needed — the implementation already matched.
- **Breadcrumbs are never queued as their own disk `Event`.** They live only in
  `BreadcrumbRingBuffer` (in-memory) until `ManualReporter.logError` (or, later, feat-009's
  crash handler) JSON-serializes a snapshot into the resulting `error` event's `breadcrumbs`
  attribute. Matches docs/00's own framing ("kotak hitam pesawat" — a flight recorder, useful
  only in the context of an incident) and MOB-13's literal wording ("dilampirkan ke setiap
  crash/error," not "dicatat sendiri"). Practical upside: a screen the app never crashes near
  never costs a disk write, however many breadcrumbs roll through the buffer. This is also why
  no *new* scrubbing code was needed — the JSON blob is just another string attribute on the
  `error` event, so it flows through `Scrubber`'s existing blanket `PatternRedactor` pass for
  free, the same as `req_headers`/`res_headers` did in feat-004's amendment.
- **`BreadcrumbRingBuffer.shared` is this SDK's first piece of genuinely ambient/global
  state.** Every other component (`sink`, `sessionManager`, `IngestEndpoint`, ...) is
  explicitly injected — no singletons. Breadcrumbs are the exception because `APM.breadcrumb`
  needs to be callable from literally anywhere in host app code with a two-argument call
  (`message`, `category`) — matching docs/02's exact documented shape — and a lock-protected
  in-memory FIFO is safe to be a singleton in a way a disk queue or network session is not
  (no I/O, no configuration, nothing that could silently diverge between two instances).
  Tests construct their own isolated `BreadcrumbRingBuffer` instances rather than touching
  `.shared`, to avoid cross-test pollution — same discipline as `UserIdentity`'s isolated
  `UserDefaults` suites in feat-006.
- **`AutomaticBreadcrumbSource`'s real OS-level triggers are honestly out of unit-test reach
  on this toolchain.** `UIApplication` lifecycle notifications need iOS (the host macOS
  `swift test` toolchain has no `UIApplication` to post them from at all — same
  host-vs-iOS gap flagged since feat-003); real `NWPathMonitor` connectivity changes can't be
  forced deterministically in a unit test even though the type is cross-platform. Rather than
  leave this untested or fake a false sense of coverage, exposed `recordLifecycle`/
  `recordConnectivity` as `internal` (not `private`) — real callbacks call them, and tests
  call them directly to verify the mapping logic. What's genuinely NOT proven by any test:
  that the real notification names/`NWPathMonitor` actually fire these methods on a real
  device — user confirmed this goes on the manual device-verification list for the pilot, not
  something to fake in tests.

**Blockers** — none.

**Files added:** `Sources/APMKit/Breadcrumbs/{Breadcrumb,BreadcrumbRingBuffer,
AutomaticBreadcrumbSource,ScreenTracking}.swift`.
`Tests/APMKitTests/Breadcrumbs/{BreadcrumbRingBufferTests,AutomaticBreadcrumbSourceTests}.swift`,
`Tests/APMKitTests/BreadcrumbLeakTests.swift`.
**Files amended:** `Sources/APMKit/APMKit.swift` (`APM.breadcrumb(_:category:level:)`);
`Sources/APMKit/Identity/ManualReporter.swift` (attaches breadcrumb snapshot);
`Tests/APMKitTests/Identity/ManualReporterTests.swift` (breadcrumb-attachment tests added).
