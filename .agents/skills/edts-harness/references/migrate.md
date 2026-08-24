# Migrate mode

Move a repo from an existing harness onto edts-harness **without losing anything**.

`create` refuses to write into a repo that already has a harness, because generating alongside
one leaves two competing instruction files — and an agent loading `CLAUDE.md` follows the old
one and never reads the new files. That failure is silent, which is what makes it dangerous.

## The rule

**Never delete. Move content to the file that now owns it.**

An old `progress.md` can hold hundreds of lines of real history — decisions, root causes,
gotchas that each cost a debugging session. That is the most valuable thing in the repo. A
tidier file layout is not worth trading it for.

**The script detects; you migrate.** Classifying prose — is this paragraph a binding rule, a
lesson, or history? — takes judgement no script has. Do it deliberately, file by file.

## Mapping

| Old | Content | New home |
|---|---|---|
| `CLAUDE.md` (full instructions) | Rules and prohibitions | `CONSTITUTION.md` |
| | Startup order, verification, done criteria | `AGENTS.md` |
| | *the file itself* | Replaced by the single line `@AGENTS.md` |
| `feature_list.json` / `TASKS.md` | Feature list, status, dependencies | `FEATURES.md` rows |
| | Per-feature evidence and narrative | `archive/features/<id>.md` |
| `progress.md` / `claude-progress.md` | Decisions that govern future work | `CONSTITUTION.md`, dated |
| | Lessons and gotchas | `JOURNAL.md`, author-stamped |
| | Session history | `archive/sessions/<date>-<topic>.md` |
| `session-handoff.md` | Current objective, next step, blockers | `state/<name>.md` |
| `init.sh` | Verification commands | `verify.sh` (usually already generated correctly) |
| `clean-state-checklist.md` | Definition of done | `AGENTS.md` |
| `quality-document.md` | Quality bar | `CONSTITUTION.md` |

## Procedure

1. **Branch first.** Migration touches every instruction file; it must be trivially revertable.
2. **Read every old file in full.** Do not skim — the value is in the details.
3. **Generate the skeleton:** `create --migrate`. It writes the new files and leaves `CLAUDE.md`
   alone, warning that it still points nowhere.
4. **Move content, one file at a time**, using the table above. Classify each paragraph:
   - a rule that constrains future work → `CONSTITUTION.md`, with a date and the reasoning
   - a lesson learned the hard way → `JOURNAL.md`, with the author
   - what happened in a session → `archive/sessions/`
   - a feature's proof → its `archive/features/<id>.md`
5. **Rewrite `CLAUDE.md` last**, once `AGENTS.md` actually carries the startup order. Replace it
   with the single line `@AGENTS.md`. Until this step the harness is unreachable and the audit
   reports CRITICAL — that is correct, not a false alarm.
6. **Move the old files to `archive/legacy/`.** Do not delete them. If content was missed, it is
   still recoverable; once you are confident, the user can delete them in their own commit.
7. **Audit.** `audit --target .` must report no CRITICAL failures before you call it migrated.

## What "done" looks like

- `audit` reports zero critical failures.
- Every decision and lesson from the old files exists somewhere in the new ones.
- `archive/legacy/` holds the originals, untouched.
- `verify.sh` runs and prints `HARNESS_VERIFY: PASS`.

## Do not

- Delete an old file before its content is in the new structure.
- Summarise away detail on the way across. "Fixed a crash" loses the root cause; the root
  cause is the part worth keeping.
- Migrate and change behaviour in the same commit. Move content first, improve it later.
