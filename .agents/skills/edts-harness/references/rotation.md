# Rotation — moving closed work to the archive

Rotation is what keeps the hot files flat. Without it, `FEATURES.md` and the state files grow
for the life of the project and every session pays to re-read finished work.

**This is a written procedure, not a script.** It is a cut-and-paste plus a link — an agent
can do it correctly, and a script would be another moving part to maintain. The audit checks
that it actually happened; if it turns out agents skip it in practice, that is the signal to
automate it, not before.

## When a feature closes

Trigger: a feature's status becomes ✅.

1. Create `archive/features/<id>.md` containing the feature's full detail — the `Done when`
   criteria, the complete evidence table, decisions, and any bug narrative.
2. Add a header line: `- **Status:** ✅ done · closed <YYYY-MM-DD> · **Depends on:** <ids>`.
3. Delete the `### <id> …` detail section from `FEATURES.md`.
4. In the summary table, set that row's **Evidence** cell to
   `[archive](archive/features/<id>.md)`.
5. Leave the summary row itself in place — the table is the project's index.

The audit's "Evidence links resolve" check fails if step 1 is skipped, so a half-done
rotation is caught rather than silently losing the proof.

## When a session ends

1. Create `archive/sessions/<YYYY-MM-DD>-<topic>.md` with the session's `Changes` table and
   what went wrong.
2. Clear the `Changes` table in your `state/<name>.md` and rewrite **Now** / **Next step** for
   the next session.

## When an epic completes

Trigger: every feature in the epic is ✅.

1. Move the whole `## Epic · <name>` section to `archive/epics/<slug>.md`.
2. Add a one-line entry under **Shipped** in `FEATURES.md` linking to it.
3. Remove the epic's row from the roll-up table at the top.

## What never rotates

- `CONSTITUTION.md` — rules and decisions stay in context permanently. If a lesson in
  `JOURNAL.md` generalised into a rule, it belongs here, not in the archive.
- `JOURNAL.md` — append-only and grepped, never read whole, so its size costs nothing.

## Why this order matters

Write the archive file **first**, then remove the detail. Doing it the other way round means a
crash or an interrupted session loses the evidence with nothing to recover it from.
