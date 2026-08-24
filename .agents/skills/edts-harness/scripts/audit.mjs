#!/usr/bin/env node
import path from 'node:path';
import { readIfExists, listStateFiles } from './lib/parse.mjs';
import { runChecks } from './lib/checks.mjs';
import { runProbe } from './lib/probe.mjs';
import { renderHtmlReport } from './lib/report.mjs';
import { writeFile } from 'node:fs/promises';

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (!t.startsWith('--')) { args._.push(t); continue; }
    const key = t.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) args[key] = true;
    else { args[key] = next; i++; }
  }
  return args;
}

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  console.log(`Usage: node audit.mjs [--target DIR] [--json] [--html FILE] [--min-score N]

Static checks only — no project commands are run.
Exit code is 1 when the score is below --min-score (default 70).`);
  process.exit(0);
}

const target = path.resolve(args.target || args._[0] || process.cwd());
const minScore = Number(args['min-score'] ?? 70);

const files = {
  claude: await readIfExists(path.join(target, 'CLAUDE.md')),
  agents: await readIfExists(path.join(target, 'AGENTS.md')),
  constitution: await readIfExists(path.join(target, 'CONSTITUTION.md')),
  features: await readIfExists(path.join(target, 'FEATURES.md')),
  journal: await readIfExists(path.join(target, 'JOURNAL.md')),
  stateFiles: await listStateFiles(target)
};

const commitIso = runProbe('git log -1 --format=%cI', target, 5000);
const newestCommit = commitIso ? new Date(commitIso) : null;

// Last commit date per state file. Filesystem mtime cannot be trusted for this:
// git checkout rewrites working-tree files and resets it.
const stateCommitDates = {};
for (const s of files.stateFiles) {
  const iso = runProbe(`git log -1 --format=%cI -- "${s.rel}"`, target, 5000);
  if (iso) stateCommitDates[s.rel] = new Date(iso);
}

const categories = runChecks({ files, target, newestCommit, stateCommitDates });

// Warnings count for half. A missing "Started by" shouldn't weigh the same as a
// dependency cycle.
const weigh = (c) => (c.pass ? 1 : c.severity === 'warn' ? 0.5 : 0);
const all = categories.flatMap((c) => c.checks);
const raw = Math.round((all.reduce((sum, c) => sum + weigh(c), 0) / all.length) * 100);

// A failed critical check means the harness is unreachable or unverifiable — an
// agent never loads it, or nothing can be proven done. Averaging that away
// produced a 97/100 "Excellent" for a harness no agent would ever read, so a
// critical failure caps the score outright.
const criticalFailures = all.filter((c) => !c.pass && c.severity === 'critical');
const overall = criticalFailures.length ? Math.min(raw, 49) : raw;

const label = criticalFailures.length
  ? 'Critical — harness not wired up'
  : overall >= 90 ? 'Excellent' : overall >= 75 ? 'Good' : overall >= 50 ? 'Needs attention' : 'Critical';

if (args.html) {
  const out = path.resolve(args.html === true ? path.join(target, 'harness-audit.html') : args.html);
  await writeFile(
    out,
    await renderHtmlReport({
      project: path.basename(target),
      overall,
      label,
      categories,
      generated: new Date().toISOString().slice(0, 16).replace('T', ' ')
    }),
    'utf8'
  );
  console.log(`HTML report written to ${out}`);
}

if (args.json) {
  console.log(JSON.stringify({ target, overall, label, categories }, null, 2));
} else {
  console.log(`\nedts-harness audit — ${path.basename(target)}`);
  console.log(`${overall}/100  ${label}\n`);

  for (const cat of categories) {
    const passed = cat.checks.filter((c) => c.pass).length;
    const pct = Math.round((passed / cat.checks.length) * 100);
    console.log(`  ${cat.name}  ${passed}/${cat.checks.length}  (${pct}%)`);
    for (const c of cat.checks) {
      if (c.pass) continue;
      const mark = c.severity === 'warn' ? 'WARN' : c.severity === 'critical' ? 'CRITICAL' : 'FAIL';
      console.log(`    ${mark}  ${c.label}`);
      console.log(`          ${c.detail}`);
      console.log(`          fix: ${c.fix}`);
    }
    console.log('');
  }

  if (criticalFailures.length) {
    console.log(`  ${criticalFailures.length} CRITICAL failure(s) — the harness is not wired up.`);
    console.log('  Score is capped until these are fixed; the other checks are moot.\n');
  }

  const failed = all.filter((c) => !c.pass);
  if (!failed.length) {
    console.log('  No issues found.\n');
  } else {
    console.log(`  ${failed.length} issue(s). Weakest area: ${
      categories
        .map((c) => ({ name: c.name, pct: c.checks.filter((x) => x.pass).length / c.checks.length }))
        .sort((a, b) => a.pct - b.pct)[0].name
    }\n`);
  }
}

if (overall < minScore) process.exitCode = 1;
