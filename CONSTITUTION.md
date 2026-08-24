# Constitution — APMKit

> **Binding.** This file owns every rule in the project. `AGENTS.md` describes *how to work*;
> this file defines *what is always true*. On any conflict, this file wins.
> Never archived, always in context. Changing a rule is a deliberate amendment — date it.

## Invariants — architecture

- Define the layer chain and make it mandatory (e.g. View → ViewModel → UseCase →
  Repository → Service). Views never skip layers.

## Invariants — platform

- **Deployment target: iOS 26.4.** Check API availability before using any
  newer SwiftUI/UIKit API.
- **Workspace only:** build via `APMKit.xcodeproj`, never the `.xcodeproj` directly.
- Pipe xcodebuild through `tee` + `grep 'BUILD SUCCEEDED'`. Piping to `tail` alone hides failures, because `set -e` only sees tail's exit code, not xcodebuild's.
- Check the real IPHONEOS_DEPLOYMENT_TARGET before using newer SwiftUI APIs. `@FocusState` is iOS 15+, `.onChange(of:perform:)` is 14+ — both fail to build on 13.
- Never open the `.xcodeproj` directly when a `.xcworkspace` exists.
- A new test file compiles but is silently NOT RUN unless it has test-target membership. Confirm the test count actually increased, not just that the suite passed.

## Prohibitions — code

- No `print()` — use OSLog if logging is genuinely needed.
- No force unwraps (`!`), force casts (`as!`), or `try!` in app code. Test mocks excepted.
- Never weaken ATS / `NSAllowsArbitraryLoads` in any Info.plist.

## Prohibitions — process

- **Never auto-commit.** Update files, report what changed, let the user decide.
- Never mark a feature ✅ without evidence recorded in `FEATURES.md`.
- One feature active at a time per person (see your `state/<name>.md`). Out-of-scope ideas
  become new `FEATURES.md` rows, not drive-by edits.

## Git

- Base branch for PRs: `develop`. Feature branches: `feature-<topic>/<detail>`.
- **Commit messages are prefixed with the feature ID:** `feat-042: <summary>`.
  This lets `git log --grep="<id>"` corroborate the `By` column in `FEATURES.md` — markdown
  gives attribution at a glance, git proves it.
- **State is one file per person:** `state/<git config user.name>.md`. You write only your own
  file; nobody else ever touches it. Because git only conflicts when two branches change the
  *same lines of the same file*, this makes **merge, rebase and cherry-pick conflict-free by
  construction** — no merge strategy, no `.gitattributes`, no per-developer setup to forget.
- **Cross-person visibility lives in `FEATURES.md`, not in state files.** `FEATURES.md` merges
  normally and shows every in-flight feature with its `By` owner. Your state file answers only
  "what am *I* doing right now." Keep a short **In flight elsewhere** note when a teammate
  picks up work you care about.
- Attribution (`By` columns, journal authors) comes from `git config user.name` on the machine
  running the session — never from the agent, so it works identically for any tool.

---

## Decisions

_Dated entries. Add one whenever an arguable choice gets settled — include the reasoning, so
it can be reopened later without redoing the analysis. Amend by adding a new dated entry that
supersedes the old one; never silently edit history._

<!-- ### YYYY-MM-DD · <short title>
     <the rule, then why it was chosen over the alternative> -->
