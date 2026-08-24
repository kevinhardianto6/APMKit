# Create mode

Scaffold a harness into a repo. Works for empty and existing projects.

## Run it

```bash
node scripts/create.mjs --target /path/to/project [--profile standard] [--dry-run]
```

| Flag | Meaning |
|---|---|
| `--target DIR` | Project to scaffold (default: cwd) |
| `--profile lite\|standard\|full` | File set (default: `standard`) |
| `--stack ID` | Force a profile instead of detecting |
| `--dry-run` | Report what would be written, change nothing |
| `--force` | Overwrite existing files — **ask the user first** |

**Always `--dry-run` first on an existing repo** and show the user the plan before writing.

## What happens

1. **Detect** — profiles are matched by `priority` (lowest first). A profile declaring
   `packageDeps` must match one, which is what stops a React app matching `node-backend`
   just because both have a `package.json`. Falls back to `generic`.
2. **Probe** — runs the profile's read-only commands in the target to discover real values:
   the actual scheme, an installed simulator, the package manager from the lockfile, which
   npm scripts exist. Probes are best-effort — a failure returns `null` and degrades the
   output rather than aborting.
3. **Render** — fills the templates and refuses to write any file that still contains a
   `{{PLACEHOLDER}}`.

`AGENTS.md`'s "Knowledge graphs" section is conditional: `create` detects whether `graphify`
and/or `code-review-graph` are already installed in the target (via `graphify-out/`, `.mcp.json`,
and git hook markers) and writes a section documenting only the tool(s) actually present. If
neither is installed, the section — and its heading — is omitted entirely rather than left as
a dangling reference. See `scripts/lib/knowledge-graphs.mjs`.

Detection is OR-based — any one signal means "installed" — so the section claims only the
integrations it actually observed, never the whole install. Hooks (`post-commit`,
`pre-commit`, `PostToolUse` in `.claude/settings.json`), the `graphify-out/` ignore rule, and
each of the four `code-review-graph` skills are checked separately. Where one is missing the
prose says so and gives the fix, because a graph the agent believes is self-updating but isn't
returns confidently wrong answers — worse than no graph. Unreadable or malformed
`.claude/settings.json` counts as "not wired", the conservative direction.

## Rules

- **Never invent a check.** If the profile's verify step needs an npm script that doesn't
  exist, the generated `verify.sh` says so instead of emitting a command that always fails.
- **Never overwrite blindly.** Existing files are skipped. `--force` requires explicit user
  consent, per file.
- **Never leave a placeholder.** `assertNoPlaceholders` throws — a silent placeholder ships
  a harness that lies about what it checks.
- **Never auto-commit** the generated files.

## After generating

The output is a skeleton, not a finished harness. Tell the user to fill in:

- `AGENTS.md` — the `TODO` project description and structure
- `CONSTITUTION.md` — real architecture invariants; the profile only supplies stack defaults
- `FEATURES.md` — the first epic, its PRD link, and real features

Then confirm `./verify.sh build` actually passes before the first feature is started.

## Adding a stack

Add one file to `profiles/`. No code changes. Shape:

```js
export default {
  id, name, priority,
  detect:  { files: [], globs: ['*.ext'], packageDeps: [] },
  probe:   { key: 'shell command', slow: { cmd: '...', timeout: 120_000 } },
  verify:  { build: '  cmd || fail "build"',
             test:  { requiresScript: 'test', block: '  {{pmRun}} test || fail "test"' } },
  pitfalls: ['Real lessons — each should have cost someone a debugging session.'],
  constitution: { architecture: '', platform: '', code: '' },
  defaults: { baseBranch, branchPattern, featureIdExample, techStack, structure }
};
```

Probe values are available to `verify` blocks and `constitution` strings as `{{key}}`.
