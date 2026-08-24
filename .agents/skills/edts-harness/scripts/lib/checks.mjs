import { existsSync, statSync } from 'node:fs';
import path from 'node:path';
import {
  splitSections,
  hasSection,
  parseFeatures,
  findCycles,
  lineCount,
  PLACEHOLDER,
  STATUS
} from './parse.mjs';

export const CAPS = { agents: 80, state: 100 };

function check(pass, label, detail, fix, severity = 'error') {
  return { pass: Boolean(pass), label, detail, fix, severity };
}

// ---------- Files & wiring ----------
function filesCategory({ files, target }) {
  const { claude, agents, constitution, features, stateFiles } = files;
  const verifyPath = path.join(target, 'verify.sh');
  const hasVerify = existsSync(verifyPath);
  let executable = false;
  if (hasVerify) {
    try { executable = Boolean(statSync(verifyPath).mode & 0o111); } catch { /* ignore */ }
  }

  return {
    id: 'files',
    name: 'Files & wiring',
    checks: [
      check(claude !== null, 'CLAUDE.md exists',
        claude !== null ? 'Present.' : 'Missing.',
        'Create CLAUDE.md containing only "@AGENTS.md".'),
      check(claude !== null && /@AGENTS\.md/.test(claude), 'CLAUDE.md points to AGENTS.md',
        claude && /@AGENTS\.md/.test(claude)
          ? 'Points to AGENTS.md.'
          : 'No @AGENTS.md line — an agent loading CLAUDE.md never reaches this harness.',
        'Put "@AGENTS.md" at the top of CLAUDE.md so both agents share one source of truth.',
        'critical'),
      check(agents !== null, 'AGENTS.md exists', agents !== null ? 'Present.' : 'Missing.',
        'Run create mode to scaffold AGENTS.md.', 'critical'),
      check(constitution !== null, 'CONSTITUTION.md exists',
        constitution !== null ? 'Present.' : 'Missing (expected on standard/full).',
        'Create CONSTITUTION.md — it owns every rule and must never be archived.'),
      check(features !== null, 'FEATURES.md exists',
        features !== null ? 'Present.' : 'Missing.',
        'Create FEATURES.md — the scope backbone with the dependency graph.'),
      check(stateFiles.length > 0, 'At least one state file',
        stateFiles.length ? `${stateFiles.length} file(s) in state/.` : 'No state/<name>.md found.',
        'Create state/<git config user.name slug>.md for the current author.'),
      check(hasVerify, 'verify.sh exists', hasVerify ? 'Present.' : 'Missing.',
        'Create verify.sh — no feature can be marked done without a runnable check.', 'critical'),
      check(!hasVerify || executable, 'verify.sh is executable',
        !hasVerify ? 'No verify.sh.' : executable ? 'Executable bit set.' : 'Not executable.',
        'chmod +x verify.sh')
    ]
  };
}

// ---------- AGENTS.md structure ----------
function agentsCategory({ files }) {
  const { agents, constitution } = files;
  const lines = lineCount(agents);
  const startup = splitSections(agents).find((s) => /session startup/i.test(s.heading));
  const verification = splitSections(agents).find((s) => /verification/i.test(s.heading));

  // Rules must live in CONSTITUTION.md only. If a rule phrase appears in both,
  // they will drift — that is the exact bug this harness was designed to avoid.
  const ruleMarkers = ['never auto-commit', 'no force unwrap', 'no `print()`', 'layer chain'];
  const duplicated = constitution
    ? ruleMarkers.filter((m) => {
        const re = new RegExp(m.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
        return agents && re.test(agents) && re.test(constitution);
      })
    : [];

  return {
    id: 'agents',
    name: 'AGENTS.md structure',
    checks: [
      check(startup, 'Session startup section present',
        startup ? `Found "${startup.heading}".` : 'No startup section.',
        'Add "## Session startup" with the ordered boot sequence.'),
      check(startup && /state\//i.test(startup.body), 'Startup reads the author state file',
        startup && /state\//i.test(startup.body) ? 'References state/.' : 'No state file step.',
        'Startup must tell the agent to read state/<its own name>.md.'),
      check(startup && /CONSTITUTION/i.test(startup.body), 'Startup reads CONSTITUTION.md',
        startup && /CONSTITUTION/i.test(startup.body) ? 'References CONSTITUTION.' : 'Missing.',
        'Add "Read CONSTITUTION.md" as a startup step.'),
      check(startup && /verify/i.test(startup.body), 'Startup runs verification',
        startup && /verify/i.test(startup.body) ? 'Runs verify.' : 'No baseline check.',
        'Add a "run verify.sh to confirm a clean baseline" startup step.'),
      check(verification && /`|```/.test(verification.body ?? ''), 'Verification commands are runnable',
        verification ? 'Commands present.' : 'No verification section.',
        'List the exact commands in a code block. A check that cannot be run is worse than none.'),
      check(hasSection(agents, 'definition of done'), 'Definition of done present',
        hasSection(agents, 'definition of done') ? 'Present.' : 'Missing.',
        'State exactly what must hold before a feature can be marked done.'),
      check(hasSection(agents, 'session handoff'), 'Session handoff present',
        hasSection(agents, 'session handoff') ? 'Present.' : 'Missing.',
        'Describe how to leave the state file resumable.'),
      check(agents !== null && lines <= CAPS.agents, 'AGENTS.md stays concise',
        agents === null ? 'Missing.' : `${lines} lines (cap ${CAPS.agents}).`,
        `Trim below ${CAPS.agents} lines — move detail into linked docs.`),
      check(duplicated.length === 0, 'Rules are not duplicated',
        duplicated.length === 0
          ? 'No rule text repeated across AGENTS.md and CONSTITUTION.md.'
          : `Repeated in both: ${duplicated.join(', ')}.`,
        'Delete the rule from AGENTS.md. CONSTITUTION.md owns rules; duplication guarantees drift.')
    ]
  };
}

// ---------- FEATURES.md format + dependency graph ----------
function featuresCategory({ files, target }) {
  const { features } = files;
  const model = features ? parseFeatures(features) : { epics: [], details: [], allRows: [] };
  const rows = model.allRows;
  const ids = new Set(rows.map((r) => r.id));

  const badStatus = rows.filter((r) => !r.status);
  const unknownDeps = rows.flatMap((r) =>
    r.dependsOn.filter((d) => !ids.has(d)).map((d) => `${r.id}→${d}`)
  );
  const cycles = findCycles(rows);

  const doneNoEvidence = rows.filter(
    (r) => r.status === '✅' && (!r.evidence || /^[—\-–]?$/.test(r.evidence.trim()))
  );

  // Done on top of not-done: almost always a mistake, and invisible without the graph.
  const doneOnOpen = rows.filter(
    (r) =>
      r.status === '✅' &&
      r.dependsOn.some((d) => ids.has(d) && rows.find((x) => x.id === d)?.status !== '✅')
  );

  const brokenLinks = rows
    .map((r) => /\]\(([^)]+)\)/.exec(r.evidence ?? '')?.[1])
    .filter(Boolean)
    .filter((rel) => !existsSync(path.join(target, rel)));

  const epicsMissingMeta = model.epics.filter((e) => !e.startedBy || !e.started);

  // A ✅ feature whose detail section is still inline was never rotated. Left
  // unchecked this is exactly how FEATURES.md grows without bound.
  const detailIds = new Set(model.details.map((d) => d.id));
  const unrotated = rows.filter((r) => r.status === '✅' && detailIds.has(r.id));

  return {
    id: 'features',
    name: 'FEATURES.md & dependency graph',
    checks: [
      check(model.epics.length > 0, 'At least one epic',
        model.epics.length ? `${model.epics.length} epic(s).` : 'No "## Epic ·" heading found.',
        'Group features under "## Epic · <name>" with a PRD link and ID prefix.'),
      check(rows.length > 0, 'At least one feature row',
        rows.length ? `${rows.length} feature(s).` : 'No rows parsed.',
        'Add rows to the epic summary table.'),
      check(badStatus.length === 0, 'Every feature has a valid status symbol',
        badStatus.length === 0
          ? `All statuses are one of ${Object.keys(STATUS).join(' ')}.`
          : `Invalid/missing on: ${badStatus.map((r) => r.id).join(', ')}.`,
        'Status must be exactly one symbol — the table is parsed, free text breaks tooling.'),
      check(unknownDeps.length === 0, 'Dependencies reference real features',
        unknownDeps.length === 0 ? 'All dependency IDs exist.' : `Unknown: ${unknownDeps.join(', ')}.`,
        'Fix the ID or add the missing feature row.'),
      check(cycles.length === 0, 'No dependency cycles',
        cycles.length === 0 ? 'Graph is acyclic.' : `Cycle: ${cycles[0].join(' → ')}.`,
        'A cycle is an impossible build order — break it.'),
      check(doneNoEvidence.length === 0, 'Done features have evidence',
        doneNoEvidence.length === 0
          ? 'Every ✅ links to or contains evidence.'
          : `No evidence: ${doneNoEvidence.map((r) => r.id).join(', ')}.`,
        'Record the proof, or move the feature back to in progress.'),
      check(doneOnOpen.length === 0, 'No feature done on top of an open dependency',
        doneOnOpen.length === 0
          ? 'No ✅ depends on unfinished work.'
          : `Suspect: ${doneOnOpen.map((r) => r.id).join(', ')}.`,
        'Either the dependency is actually finished, or this feature was closed too early.'),
      check(brokenLinks.length === 0, 'Evidence links resolve',
        brokenLinks.length === 0 ? 'All archive links exist.' : `Missing: ${brokenLinks.join(', ')}.`,
        'Create the archive file or fix the path — a dead evidence link is an unprovable ✅.'),
      check(unrotated.length === 0, 'Closed features are rotated to archive/',
        unrotated.length === 0
          ? 'No ✅ feature still carries an inline detail section.'
          : `Not rotated: ${unrotated.map((r) => r.id).join(', ')}.`,
        'Move the detail to archive/features/<id>.md and replace the Evidence cell with a link. See references/rotation.md.'),
      check(epicsMissingMeta.length === 0, 'Epics record Started / Started by',
        epicsMissingMeta.length === 0
          ? 'All epics carry start metadata.'
          : `Missing on: ${epicsMissingMeta.map((e) => e.name).join(', ')}.`,
        'Add "**Started:** YYYY-MM-DD · **Started by:** <name>" to the epic header.',
        'warn')
    ],
    model
  };
}

// ---------- Drift & quality ----------
function driftCategory({ files, target, featuresModel, newestCommit, stateCommitDates }) {
  const { agents, constitution, features, stateFiles } = files;
  const all = [agents, constitution, features, ...stateFiles.map((s) => s.content)]
    .filter(Boolean)
    .join('\n');
  const leftovers = [...new Set([...all.matchAll(PLACEHOLDER)].map((m) => m[0]))];

  const oversized = stateFiles.filter((s) => lineCount(s.content) > CAPS.state);
  const ids = new Set((featuresModel?.allRows ?? []).map((r) => r.id));
  const badActive = stateFiles
    .map((s) => {
      const m = /Active feature:\*{0,2}\s*`?([A-Za-z][A-Za-z0-9]*-?\d+)`?/i.exec(s.content);
      return m && ids.size && !ids.has(m[1]) ? `${s.name}→${m[1]}` : null;
    })
    .filter(Boolean);

  // Compare each state file's last COMMIT date against the newest commit.
  // Filesystem mtime is useless here: `git checkout` rewrites working-tree
  // files, so switching branches would silently "fix" a stale state file.
  const stale = newestCommit
    ? stateFiles.filter((s) => {
        const committed = stateCommitDates?.[s.rel];
        return committed ? committed < newestCommit : false;
      })
    : [];

  return {
    id: 'drift',
    name: 'Drift & quality',
    checks: [
      check(leftovers.length === 0, 'No template placeholders left',
        leftovers.length === 0 ? 'No {{...}} tokens.' : `Found: ${leftovers.join(', ')}.`,
        'Replace every placeholder — a leftover ships a harness that lies about what it checks.'),
      check(oversized.length === 0, 'State files stay under cap',
        oversized.length === 0
          ? `All state files ≤ ${CAPS.state} lines.`
          : `Over cap: ${oversized.map((s) => `${s.name} (${lineCount(s.content)})`).join(', ')}.`,
        `Rotate finished work into archive/ so state stays under ${CAPS.state} lines.`),
      check(badActive.length === 0, 'Active features exist in FEATURES.md',
        badActive.length === 0 ? 'Active features resolve.' : `Unknown: ${badActive.join(', ')}.`,
        'The state file points at a feature ID that is not in FEATURES.md.'),
      check(stale.length === 0, 'State files are fresher than the newest commit',
        !newestCommit
          ? 'Not a git repo — skipped.'
          : stale.length === 0
            ? 'State files updated at or after the last commit.'
            : `Stale: ${stale.map((s) => s.name).join(', ')}.`,
        'Work happened without updating state — update it before ending the session.',
        'warn')
    ]
  };
}

export function runChecks(ctx) {
  const files = filesCategory(ctx);
  const agents = agentsCategory(ctx);
  const features = featuresCategory(ctx);
  const drift = driftCategory({ ...ctx, featuresModel: features.model });
  return [files, agents, features, drift];
}
