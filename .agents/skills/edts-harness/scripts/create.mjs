#!/usr/bin/env node
import path from 'node:path';
import { loadProfiles, detectStack } from './lib/detect.mjs';
import { runProbes, gitUser, pickScheme, pickSimulator, parseScripts, slugifyUser } from './lib/probe.mjs';
import { detectLegacy, formatLegacyReport } from './lib/legacy.mjs';
import { detectKnowledgeGraphs, buildKnowledgeGraphsSection } from './lib/knowledge-graphs.mjs';
import {
  render,
  assertNoPlaceholders,
  readTemplate,
  writeOut,
  buildVerifyBlocks
} from './lib/render.mjs';

const TIERS = {
  lite: ['CLAUDE.md', 'AGENTS.md', 'state', 'verify.sh'],
  standard: ['CLAUDE.md', 'AGENTS.md', 'CONSTITUTION.md', 'FEATURES.md', 'state', 'verify.sh', 'archive'],
  full: ['CLAUDE.md', 'AGENTS.md', 'CONSTITUTION.md', 'FEATURES.md', 'state', 'verify.sh', 'archive', 'JOURNAL.md', 'evaluator-rubric.md']
};

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
  console.log(`Usage: node create.mjs [--target DIR] [--profile lite|standard|full]
                      [--stack ID] [--dry-run] [--force]

Detects the stack, probes the environment, and writes the harness files.
Existing files are skipped unless --force.

If the repo already has a harness, create refuses to write and prints a
migration plan instead. Use --migrate to acknowledge and generate anyway.`);
  process.exit(0);
}

const target = path.resolve(args.target || args._[0] || process.cwd());
const tier = TIERS[args.profile] ? args.profile : 'standard';
const dryRun = Boolean(args['dry-run']);
const force = Boolean(args.force);

// A repo that already has a harness must not be half-written into. Generating
// alongside an existing CLAUDE.md leaves two competing instruction files, and
// the agent follows the old one — a silent, total failure.
const legacy = await detectLegacy(target);
if (legacy.hasLegacy && !args.migrate && !dryRun) {
  console.log(`edts-harness — refusing to write in ${target}\n`);
  console.log(formatLegacyReport(legacy));
  console.log('  This repo already has a harness. Writing new files alongside it would leave');
  console.log('  two competing sets of instructions.\n');
  console.log('  Migrate instead — see references/migrate.md. Nothing is deleted; content moves');
  console.log('  to the file that now owns it, and the old files land in archive/legacy/.\n');
  console.log('  To generate anyway once you have read that: --migrate');
  process.exit(2);
}

const profiles = await loadProfiles();
const profile = args.stack
  ? profiles.find((p) => p.id === args.stack) ?? (await detectStack(target, profiles))
  : await detectStack(target, profiles);

const probes = runProbes(profile, target);
const user = gitUser(target) ?? 'unknown';
const userSlug = slugifyUser(user);
const scripts = parseScripts(probes.scriptsJson);
const today = new Date().toISOString().slice(0, 10);

// Stack-specific derivations from raw probe output.
const scheme = pickScheme(probes.schemesJson);
const simulator = pickSimulator(probes.simulatorsJson);
const pm = probes.packageManager ?? 'npm';

const probeValues = {
  ...probes,
  scheme: scheme ?? 'TODO-scheme',
  destination: simulator ? `platform=iOS Simulator,name=${simulator}` : 'platform=iOS Simulator,name=TODO',
  workspace: probes.workspace ?? probes.project ?? 'TODO.xcworkspace',
  deploymentTarget: (probes.deploymentTarget ?? 'unknown').replace('IPHONEOS_DEPLOYMENT_TARGET = ', 'iOS '),
  packageManager: pm,
  pmRun: pm === 'npm' ? 'npm run' : `${pm} run`,
  nodeVersion: probes.nodeVersion ?? 'unknown'
};

// Any probe that failed must still resolve to something. A missing toolchain is
// normal — you should be able to scaffold a Flutter harness on a machine without
// Flutter installed — and an unresolved {{token}} would abort generation.
for (const key of Object.keys(probeValues)) {
  if (probeValues[key] === null || probeValues[key] === undefined) {
    probeValues[key] = 'not detected';
  }
}

const blocks = buildVerifyBlocks(profile, probeValues, scripts);
const d = profile.defaults ?? {};

const verifyList = Object.entries(blocks)
  .filter(([, b]) => !b.includes('No ') && !b.includes('TODO'))
  .map(([mode]) => `./verify.sh ${mode}`);

const rulesPointer = `**All binding rules live in \`CONSTITUTION.md\`** — architecture, platform constraints, code
prohibitions, process, and git. It is binding, not advisory: read it at startup (step 3),
and if anything in this file appears to conflict with it, **\`CONSTITUTION.md\` wins.**

Rules are deliberately not repeated here. One home, no drift.`;

const inlineRules = [
  render(profile.constitution?.architecture ?? '', probeValues),
  render(profile.constitution?.platform ?? '', probeValues),
  render(profile.constitution?.code ?? '', probeValues),
  ...(profile.pitfalls ?? []).map((p) => `- ${p}`)
].filter(Boolean).join('\n');

const values = {
  PROJECT_NAME: path.basename(target),
  PROJECT_DESCRIPTION: 'TODO: one line describing what this project is.',
  TECH_STACK: render(d.techStack ?? profile.name, probeValues),
  PROJECT_STRUCTURE: d.structure ?? 'TODO: describe the folder layout.',
  VERIFY_PRIMARY: verifyList[0] ?? './verify.sh build',
  VERIFY_COMMANDS: (verifyList.length ? verifyList : ['./verify.sh build']).join('\n'),
  RULES_SECTION: tier === 'lite' ? inlineRules : rulesPointer,
  KNOWLEDGE_GRAPHS_SECTION: buildKnowledgeGraphsSection(detectKnowledgeGraphs(target), target, tier),

  ARCHITECTURE_INVARIANTS: render(profile.constitution?.architecture ?? '', probeValues),
  PLATFORM_INVARIANTS: [
    render(profile.constitution?.platform ?? '', probeValues),
    ...(profile.pitfalls ?? []).map((p) => `- ${p}`)
  ].filter(Boolean).join('\n'),
  CODE_PROHIBITIONS: render(profile.constitution?.code ?? '', probeValues),
  BASE_BRANCH: d.baseBranch ?? 'main',
  BRANCH_PATTERN: d.branchPattern ?? 'feature/<topic>',
  FEATURE_ID_EXAMPLE: d.featureIdExample ?? 'feat-001',

  EPIC_NAME: 'First epic',
  FEATURE_COUNT: '1',
  PRD_PATH: '_none yet_',
  ID_PREFIX: 'feat-',
  TODAY: today,
  GIT_USER: user,
  FEATURE_NAME: 'Describe the first feature',
  DONE_CRITERIA: 'Define what proves this feature is finished.',
  FIRST_CHECK: 'Define the first check',

  OBJECTIVE: 'TODO: what are you trying to achieve?',
  NEXT_STEP: 'Pick the first feature from FEATURES.md and set it to in progress.',

  VERIFY_BUILD: './verify.sh build',
  VERIFY_TEST: './verify.sh test',

  BUILD_BLOCK: blocks.build,
  TEST_BLOCK: blocks.test,
  LINT_BLOCK: blocks.lint
};

const wanted = TIERS[tier];
const plan = [];
if (wanted.includes('CLAUDE.md')) plan.push(['CLAUDE.md.template', 'CLAUDE.md']);
if (wanted.includes('AGENTS.md')) plan.push(['AGENTS.md.template', 'AGENTS.md']);
if (wanted.includes('CONSTITUTION.md')) plan.push(['CONSTITUTION.md.template', 'CONSTITUTION.md']);
if (wanted.includes('FEATURES.md')) plan.push(['FEATURES.md.template', 'FEATURES.md']);
if (wanted.includes('JOURNAL.md')) plan.push(['JOURNAL.md.template', 'JOURNAL.md']);
if (wanted.includes('evaluator-rubric.md')) plan.push(['evaluator-rubric.md.template', 'evaluator-rubric.md']);
if (wanted.includes('state')) plan.push(['state.md.template', path.join('state', `${userSlug}.md`)]);
if (wanted.includes('verify.sh')) plan.push(['verify.sh.template', 'verify.sh']);

const results = [];
for (const [tpl, dest] of plan) {
  const raw = await readTemplate(tpl);
  const out = render(raw, values);
  assertNoPlaceholders(out, dest);
  results.push(await writeOut(target, dest, out, { force, dryRun }));
}

if (wanted.includes('archive')) {
  for (const sub of ['features', 'sessions']) {
    results.push(
      await writeOut(target, path.join('archive', sub, '.gitkeep'), '', { force, dryRun })
    );
  }
}

if (legacy.hasLegacy) {
  console.log(formatLegacyReport(legacy));
}

console.log(`edts-harness — ${dryRun ? 'dry run' : 'created'} in ${target}`);
console.log(`  stack:   ${profile.name} (${profile.id})`);
console.log(`  profile: ${tier}`);
console.log(`  author:  ${user}  ->  state/${userSlug}.md`);
if (profile.id === 'ios-xcode') {
  console.log(`  probed:  scheme=${scheme ?? 'none'} simulator=${simulator ?? 'none'}`);
}
console.log('');
for (const r of results) {
  console.log(`  ${r.status.toUpperCase().padEnd(11)} ${r.path}${r.reason ? ` (${r.reason})` : ''}`);
}
if (legacy.claudeConflict) {
  console.log('\n  ! CLAUDE.md was left untouched and does NOT point to AGENTS.md.');
  console.log('    Until you fix that, an agent loading CLAUDE.md follows the OLD harness');
  console.log('    and never reads what was just generated. Audit will report CRITICAL.');
}
if (profile.id === 'generic') {
  console.log('\n  ! Stack not detected — verify.sh is TODO-marked and will fail until you fill it in.');
}
