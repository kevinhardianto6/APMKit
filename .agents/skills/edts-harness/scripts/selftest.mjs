#!/usr/bin/env node
// End-to-end self test: generate a harness into a throwaway repo, then audit it.
// If the tool cannot produce a harness that passes its own audit, it is broken.
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const MIN_SCORE = 90;

const failures = [];
function expect(condition, message) {
  if (!condition) failures.push(message);
}

const dir = await mkdtemp(path.join(tmpdir(), 'edts-harness-selftest-'));

try {
  await writeFile(
    path.join(dir, 'package.json'),
    JSON.stringify({ name: 'fixture', scripts: { build: 'true', test: 'true' } }, null, 2)
  );
  execFileSync('git', ['init', '-q'], { cwd: dir });
  execFileSync('git', ['config', 'user.name', 'Self Test'], { cwd: dir });

  const created = execFileSync(
    'node',
    [path.join(HERE, 'create.mjs'), '--target', dir, '--profile', 'full'],
    { encoding: 'utf8' }
  );
  expect(/node-tool/.test(created), 'expected the node-tool profile to be detected');
  expect(/state\/self-test\.md/.test(created), 'expected the username to be slugified');

  const audited = execFileSync(
    'node',
    [path.join(HERE, 'audit.mjs'), '--target', dir, '--json'],
    { encoding: 'utf8' }
  );
  const report = JSON.parse(audited);
  expect(
    report.overall >= MIN_SCORE,
    `a freshly generated harness scored ${report.overall}, below ${MIN_SCORE}`
  );

  for (const cat of report.categories) {
    for (const c of cat.checks) {
      if (!c.pass) failures.push(`${cat.name}: ${c.label} — ${c.detail}`);
    }
  }
} finally {
  await rm(dir, { recursive: true, force: true });
}

if (failures.length) {
  console.error('SELFTEST: FAIL');
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log('SELFTEST: PASS — generated a full harness that scores 100 on its own audit');
