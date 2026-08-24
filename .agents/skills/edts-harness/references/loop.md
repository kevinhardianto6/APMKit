# Loop mode

The working session in a harnessed repo. Start → work → verify → hand off.

The project's own `AGENTS.md` is authoritative — it carries the real verification commands
and the startup order. This file explains the *reasoning* behind each step, so you know what
to do when reality does not match the script.

## Session start

1. **Resolve your state file** — `state/<git config user.name, slugified>.md`. Read it in
   full. It is the only state file you read, and you never write to anyone else's.
2. **Read `CONSTITUTION.md`** — rules and past decisions. Binding. If `AGENTS.md` seems to
   contradict it, the constitution wins.
3. **Run the verification command** from `AGENTS.md` to confirm a clean baseline. If it fails
   *before you have changed anything*, fix that first and do not take new scope — otherwise
   you cannot tell your breakage from pre-existing breakage.
4. **Pick one ready feature** from `FEATURES.md` — one whose `Depends on` are all ✅. If a
   feature is 🔴 blocked or 🟠 parked, **ask the user** whether to resume it or work something
   else. Never silently pick.
5. **Set it 🔵 immediately**, before any code changes, and record it as the active feature in
   your state file. Status reflects reality in real time, not at session end.

## During the session

- **After every meaningful edit**, append to the `Changes` table in your state file:
  file · what · why. Not batched at the end — an interrupted session must still leave a true
  record. `git diff --stat` is the ground truth this table is checked against.
- **Stay on the active feature.** An out-of-scope idea becomes a new 🟡 row in `FEATURES.md`,
  never a drive-by edit. Scope creep is the failure this rule exists to prevent.
- **Record decisions where they belong**: a choice that governs future work goes in
  `CONSTITUTION.md` with a date and a reason; a lesson learned goes in `JOURNAL.md` with your
  name; the story of this specific feature stays in its `FEATURES.md` detail section.
- **Flip status the moment it changes** — 🔴 when a blocker appears, with the blocker named.

## Session end

1. **Run verification again.** Record the exact result line as evidence — not "tests passed"
   but `HARNESS_VERIFY: PASS (test)`.
2. **Set the honest status.** ✅ only when every `Done when` criterion is met and evidence is
   recorded. If a check is deferred (no test account, no device, waiting on a teammate), the
   feature is 🟠 with the pending item named — never silently ✅.
3. **Rotate** if the feature closed — see [rotation.md](rotation.md). Archive file first, then
   remove the inline detail.
4. **Leave the state file resumable.** A fresh session with no chat history must be able to
   read it and start. "Continue the feature" is useless; "add the SPM dependency to
   User/Package.swift, then build the Service layer method" is resumable.
5. **Do not commit** unless the user asks. Report what changed and let them decide.

## When things do not fit the script

- **Baseline already broken** → surface it, fix it, do not absorb it into your feature.
- **The feature is bigger than it looked** → split it. Add the overflow as new rows rather
  than quietly expanding scope.
- **You cannot verify** → that is 🟠 with the reason, not ✅ with an excuse. The whole point of
  the harness is that "done" means proven.
- **The harness itself is wrong** (a rule that no longer holds, a stale command) → say so.
  Fixing the harness is legitimate work; silently ignoring it is how harnesses rot.
