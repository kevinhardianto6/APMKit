# Audit mode

Score harness health and surface drift.

**Explicit request only.** Never run this on your own initiative — not after create, not at
the end of a session. Only when the user asks to audit, check, or score the harness.

## Run it

```bash
node scripts/audit.mjs --target /path/to/project [--json] [--min-score 70]
```

Static checks only — **no project commands are executed**. Auditing is safe on any repo.
Exit code is 1 below `--min-score` (default 70), so it can gate CI.

## Categories

| Category | Answers |
|---|---|
| **Files & wiring** | Do the files exist, is `CLAUDE.md` pointing at `AGENTS.md`, is `verify.sh` executable |
| **AGENTS.md structure** | Startup sequence, runnable verification, definition of done, line cap, no duplicated rules |
| **FEATURES.md & dependency graph** | Valid status symbols, dependency integrity, cycles, evidence |
| **Drift & quality** | Leftover placeholders, oversized state, stale state, dangling references |

Warnings weigh half a point. A missing `Started by` should not score the same as a cycle.

## The checks that matter most

These catch real defects a structural checklist misses:

- **Dependency cycle** — an impossible build order. Reported with the full path.
- **Done on top of an open dependency** — either the dependency is actually finished, or the
  feature was closed too early. Almost always a mistake, and invisible without the graph.
- **Done with no evidence** — an unprovable ✅, which is the exact failure the harness exists
  to prevent.
- **Evidence link does not resolve** — the archive file was never written, so the proof is gone.
- **Rule duplicated across `AGENTS.md` and `CONSTITUTION.md`** — guaranteed to drift. Rules
  live in `CONSTITUTION.md` and nowhere else.
- **State file over cap** — finished work was never rotated to `archive/`, so the file read
  every session keeps growing. This is the bug that motivated the whole hot/cold split.
- **State file older than the newest commit** — work happened without updating state.

## Reporting back

Tell the user three things, in this order:

1. The overall score and label.
2. The weakest category.
3. The top 2–3 fixes, quoting the `fix:` line for each.

If they want the fixes applied, that is create mode (for missing files) or a normal edit
(for content). Do not silently fix things during an audit — the audit reports, it does not act.
