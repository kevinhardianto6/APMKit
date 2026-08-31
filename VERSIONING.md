# Versioning & Compatibility — APM Kit iOS SDK

feat-013, MOB-24. What the version number promises, and how the SDK is distributed.

## Semantic versioning

`MAJOR.MINOR.PATCH`. Current: **1.0.0** (`Sources/APMKit/Core/SDKInfo.swift`,
`APMKit.podspec`).

- **MAJOR** — a breaking change. Breaking means: a public API is removed or its signature
  changes incompatibly, the minimum supported iOS version is raised, or the wire schema
  (docs/01) changes in a way an unmodified older SDK version could no longer talk to the
  current backend contract. Adopting teams should expect to review release notes and possibly
  change call sites before upgrading a major version.
- **MINOR** — new capability, backward compatible. A new public method, a new optional
  parameter with a default, a new event type — anything an existing integration keeps working
  through without any code change.
- **PATCH** — bug fixes and internal changes with no public API or behavior change an
  integrator would need to react to.

**Breaking changes only land in a major version. No exceptions** — this is what lets an
adopting team pin `~> 1.0` (CocoaPods) or `from: "1.0.0"` (SPM) and upgrade patches/minors
automatically without re-reviewing every release.

## Two manifests, one version — kept in sync by a test, not by hand alone

The SDK ships two package manifests that both encode the current version:
`Sources/APMKit/Core/SDKInfo.swift` (`SDKInfo.current.version`, sent as the `X-APM-Sdk` header
on every request — docs/01 §7/§9) and `APMKit.podspec` (`s.version`, CocoaPods' own version
field). Nothing in either package manager keeps these in sync automatically — they're
independent, hand-edited literals. `Tests/APMKitTests/VersioningTests.swift` asserts they
match, so a release that bumps one and forgets the other fails `./verify.sh test` rather than
silently shipping a CocoaPods release whose `X-APM-Sdk` header reports the wrong version.

**Release checklist, until this is automated further:**
1. Bump `SDKInfo.current.version` in `Sources/APMKit/Core/SDKInfo.swift`.
2. Bump `s.version` in `APMKit.podspec` to match.
3. Run `./verify.sh all` — `VersioningTests` fails the build if these two drift.
4. Tag the release commit `<version>` (e.g. `1.0.0`) — both distribution channels resolve
   against this tag (SPM via `.package(url:from:)`, CocoaPods via `s.source[:tag]`).

## Distribution

- **Swift Package Manager** — primary, already the build system this repo uses
  (`Package.swift`). Verified this feature: a real external consumer (a separate package,
  depending via a genuine `git`+tag URL, not a local path) resolves, fetches, and links
  cleanly against a tagged commit of this repo, transitively resolving KSCrash too.
- **CocoaPods** — `APMKit.podspec`, verified via `./verify.sh podspec` (`pod lib lint`).
  Depends on `KSCrash/Recording` (matching `Package.swift`'s SPM product dependency exactly —
  neither package manager pulls in more of KSCrash than the other).

  **Real compatibility finding, not a hypothetical:** CocoaPods' `KSCrash` pod exposes one
  umbrella Swift module named `KSCrash`, regardless of which subspec is depended on — unlike
  SPM, which exposes each product as its own separately-importable module
  (`import KSCrashRecording` for the `Recording` product). Every file in this SDK that touches
  KSCrash now imports conditionally:
  ```swift
  #if canImport(KSCrashRecording)
  import KSCrashRecording  // SPM
  #else
  import KSCrash            // CocoaPods
  #endif
  ```
  This was found and fixed *in this feature* by actually running `pod lib lint` against the
  real podspec, not by inspecting KSCrash's packaging and assuming it would work — the first
  lint attempt failed with `Unable to resolve module dependency: 'KSCrashRecording'` even
  though the exact same code compiles cleanly under SPM. If a future KSCrash upgrade changes
  its CocoaPods module layout, `./verify.sh podspec` re-proves this rather than assuming it
  still holds.

- **`homepage`/`source` URLs in `APMKit.podspec`** point to the real repository
  (`github.com/kevinhardianto6/APMKit`, added 2026-08-31) — no longer the `REPLACE_ORG`
  placeholder `pod lib lint` tolerated during pre-release validation. `pod spec lint` at
  publish time (unlike `pod lib lint` used here) requires a reachable, tagged source, so this
  had to be resolved before an actual CocoaPods release regardless.

## Integration friction — flagged for MOB-25 ("integration in under 30 minutes")

Reviewed the full current public API surface with that target in mind, since this feature is
the first thing another team's integration actually touches. **This SDK has no composition
root** — every capability is its own independent call needing manually-constructed
dependencies, consistently noted as a deliberate, not-yet-filled gap across the codebase's own
comments (`ManualReporter`, `APMKit.swift`: "no composition root yet"). A from-scratch
integration needs, in order: construct a `SessionManager`; construct a `FileDiskQueue` (pick a
directory); wrap it in `Scrubber(downstream: DiskQueueEventSink(...))`; optionally wrap *that*
in `KillSwitch` if using remote config; construct an `EnvelopeFactory`; construct
`IngestClient` + `SyncEngine`, call `.start()`, and manually wire `SyncEngine
.appDidEnterBackground()`/`.connectivityRestored()` to real `UIApplication`/`NWPathMonitor`
notifications yourself (`AutomaticBreadcrumbSource` does *not* do this — it only handles
breadcrumbs); call `APM.instrumentedSession(...)`; call `APM.installCrashReporting(...)`; call
`APM.startHangDetection(...)`; call `APM.fetchRemoteConfig(...)`; call
`APM.recordFirstFrame(...)` from a `CATransaction` completion. That's roughly a dozen manually-
wired pieces before an app captures its first event.

**This is a real risk to the MOB-25 target, not a hypothetical one** — flagging it rather than
silently building a fix, since a composition root (something like a single
`APM.start(configuration:)` that owns and wires all of the above) is real design work outside
this feature's stated scope (distribution packaging, not API ergonomics) and deserves its own
scoped feature and review, not a drive-by addition here. Worth raising before MOB-25's sample
app / integration docs get written, since a "one call to `APM.start(...)`" composition root
would change what those docs need to say.
