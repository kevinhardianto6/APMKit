# State — Kevin Hardianto

> Your personal working state. One file per person (`state/<git config user.name>.md`),
> so merge / rebase / cherry-pick never conflict — nobody else ever writes here.
> Keep it small — cap ~100 lines. Finished work rotates to `archive/`.
> Team-wide view of who's doing what lives in `FEATURES.md`, not here.

## Now

- **Objective:** No epic in progress. Last session's work (`user_id_source` + `sdk.health`,
  MOB-27/28 extended) is done, approved, and committed as `9b4d4dd`.
- **Active feature:** none.
- **Status:** —
- **Last verify:** `./verify.sh build`/`test`/`budget` → all PASS, 2026-09-02. 248 tests.

## Next step

**Android port, in its own (separate) repo — explicitly not this one.** User said so directly
after approving the last commit. Nothing else is queued here. If a future session in *this*
repo is asked to start Android work, that's a scope violation — point back to this note and
confirm with the user first.

Parity notes for whoever picks up the Android work: `archive/epics/phase-1-2-wrap-up.md`. Two
iOS-side additions since that doc was written were deliberately designed with Android parity in
mind and are worth re-reading before scoping: the `termination` event type (maps cleanly to
`ApplicationExitInfo`) and `logError`'s auto-captured `source_file`/`source_function`/
`source_line` (Android's equivalent: a stack-frame-derived class/method, not `#fileID`).

## Parked

- **Android port** — see above. Not started, not scoped here.

## In flight elsewhere

- None.

## Blockers

- None.

## Changes (this session)

Nothing new — this was a short close-out turn. Commit `9b4d4dd` (`feat: MOB-27/MOB-28
extended, docs/01 §2.2/§2.3 — user_id_source, sdk.health`) was made per the user's explicit
approval, carrying forward everything recorded in the previous state-file entry (now
superseded by this one — see `git log` / `git show 9b4d4dd` for the full diff if needed).

One correction added to `CONSTITUTION.md` (new dated entry, not a silent edit of the old one):
the "pilot server stores the envelope verbatim" assumption from the prior decision entry was
wrong — `store()` maps named columns, not arbitrary fields. It worked end to end only because
the user had already added the `user_id_source` column, a separate `sdk_health` table, and a
`GET /v1/apps/{id}/integration` endpoint server-side before asking for this change. Process
lesson recorded: never assert a downstream system's behavior this repo can't see into — ask.

_Ground truth: run `git diff --stat` to confirm this table matches reality (should be empty —
everything from this session is committed)._
