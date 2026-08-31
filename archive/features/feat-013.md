# feat-013 · Distribution (CocoaPods + semver)

- **Status:** ✅ done · closed 2026-08-30 · **Depends on:** feat-001..010 (packages the whole
  SDK as it exists today)
- **Requirements:** MOB-23 — CocoaPods distribution alongside the existing SPM support. MOB-24
  — semver policy, a compatibility/changelog document, and the rule that breaking changes only
  land at a major version.
- **Done when:** a generated podspec passes local validation; a versioning document exists.
  **Met** — and along the way, found and fixed a real cross-package-manager incompatibility
  that would have broken CocoaPods integrators, not a hypothetical one.

## The user's explicit checkpoints, in order

**1. SPM resolves cleanly as a dependency from another project, not just locally.** Verified
with real git+tag mechanics, not a local path dependency (which every prior feature's
scratchpad harnesses used and which doesn't exercise the same code path a real consumer does):
created a bare clone of this repo, tagged it `1.0.0`, then built a separate throwaway consumer
package elsewhere depending on it via `.package(url: "file://.../apmkit-bare.git", from:
"1.0.0")` — a genuine `git`-protocol fetch-and-resolve-by-tag, transitively resolving KSCrash
too. `Package.resolved` shows a real revision pin, not a symlink. The built consumer binary
ran and printed `SDKInfo.current.version` (`1.0.0`), confirming actual linkage, not just a
successful `swift build` exit code.

**2. CocoaPods podspec, with KSCrash declared correctly.** `APMKit.podspec` added, depending
on `KSCrash/Recording` (`>= 2.1.0`) — the exact same subspec/version floor `Package.swift`
depends on via SPM's `Recording` product, so neither package manager pulls in more of KSCrash
than the other (CocoaPods' default `KSCrash` pod alone would additionally pull in Filters/
Sinks/Installations/DemangleFilter, code SPM consumers never link).

**Real finding, not assumed compatible:** the first `pod lib lint` run failed —
`error: unable to resolve module dependency: 'KSCrashRecording'` — even though the identical
source compiles cleanly under SPM. Root cause, confirmed by inspecting the actual generated
module maps (`--no-clean`): CocoaPods' `KSCrash` pod produces **one umbrella Swift module
named `KSCrash`**, regardless of which subspec(s) are pulled in — unlike SPM, which exposes
each product as its own separately-importable module (`Recording` → `import
KSCrashRecording`). Every file that touches KSCrash (`APMKit.swift`, `CrashReporter.swift`,
`CrashReportSource.swift`, `CrashUserInfoStore.swift`, `HangObserving.swift`) now imports
conditionally:
```swift
#if canImport(KSCrashRecording)
import KSCrashRecording  // SPM
#else
import KSCrash            // CocoaPods
#endif
```
`pod lib lint` passes clean after this fix. This is exactly the kind of thing that only shows
up by actually running the tool against the real manifest — reading KSCrash's podspec
structure alone (which does define per-subspec `configure_subspec` module names) suggested
per-subspec modules *should* exist; they don't, in practice, for a consumer depending on a
single subspec the way this SDK does. `VERSIONING.md` documents the finding so a future
KSCrash upgrade that changes packaging gets caught by `./verify.sh podspec`, not assumed.

**3. Semver + compatibility doc (MOB-24).** `VERSIONING.md` — what MAJOR/MINOR/PATCH promise,
current version (1.0.0, matching `SDKInfo.current.version`), and the two-manifest-one-version
problem: `SDKInfo.swift` and `APMKit.podspec` both hand-encode the version with nothing
keeping them in sync automatically. Added `Tests/APMKitTests/VersioningTests.swift` to lock
that: reads `APMKit.podspec`'s `s.version` off disk and asserts it matches
`SDKInfo.current.version` — verified this actually catches drift, not just passes trivially
(bumped the podspec version standalone, watched the test fail with a clear message, reverted).

**4. Integration friction, flagged for MOB-25 ("under 30 minutes").** Reviewed the full
current public API surface with that target in mind, since this is the first feature another
team's integration actually touches. Finding: **this SDK has no composition root** — every
capability (network capture, crash reporting, hang detection, remote config, cold-start,
manual APIs) is its own independently-constructed dependency graph, a pattern the codebase's
own comments have flagged as a known gap since feat-006 ("no composition root yet"). A
from-scratch integration needs roughly a dozen manually-wired pieces (`SessionManager`,
`FileDiskQueue`, `Scrubber`/`KillSwitch` chain, `EnvelopeFactory`, `IngestClient`/`SyncEngine`
+ manually wiring its background/connectivity triggers — `AutomaticBreadcrumbSource` does
*not* do this — then five separate `APM.*` calls) before the first event is captured. Full
detail in `VERSIONING.md` → "Integration friction." **Not fixed here** — a composition root
(e.g. one `APM.start(configuration:)`) is real design work outside this feature's scope
(packaging, not API ergonomics) and belongs in its own scoped feature with its own review, not
a drive-by addition. Flagged explicitly for the user before MOB-25's sample app/docs get
written, since a composition root would change what those need to say.

## Verification

186 tests (was 185 at feat-012's close; +1, `VersioningTests`). `./verify.sh all` →
`HARNESS_VERIFY: PASS (all)` (now five sub-checks: build/test/lint/budget/podspec). `pod lib
lint APMKit.podspec` passes clean. External SPM consumption verified via a real git+tag fetch
(see above), not just `swift build` inside this repo.

**Known placeholder, flagged loudly rather than left silent:** `APMKit.podspec`'s
`homepage`/`source` URLs use `REPLACE_ORG` — this repo has no established GitHub org/remote.
`pod lib lint` only warns (doesn't fail) on an unreachable URL, which is why validation still
passes; a real `pod spec lint` at actual publish time needs the real URL. Documented in
`VERSIONING.md`, not hidden.

**Decisions** — depend on `KSCrash/Recording` specifically (not the default `KSCrash` pod) to
match SPM's footprint exactly; conditional import as the fix for the module-name mismatch
rather than picking one package manager's naming and living with a broken other one.
**Blockers** — none.

**Files added:** `APMKit.podspec`, `VERSIONING.md`, `Tests/APMKitTests/VersioningTests.swift`.
**Files amended:** `Sources/APMKit/APMKit.swift`, `Sources/APMKit/Crash/{CrashReporter,
CrashReportSource,CrashUserInfoStore}.swift`, `Sources/APMKit/Stability/HangObserving.swift`
(conditional KSCrash import), `verify.sh` (+`podspec` mode), `AGENTS.md` (Verification
section).
