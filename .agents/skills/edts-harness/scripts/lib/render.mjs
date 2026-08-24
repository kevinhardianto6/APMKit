import { readFile, writeFile, mkdir, chmod } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const TEMPLATES_DIR = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  'templates'
);

const PLACEHOLDER = /\{\{([A-Za-z0-9_]+)\}\}/g;

export function render(template, values) {
  return template.replace(PLACEHOLDER, (match, key) => {
    const v = values[key];
    return v === undefined || v === null ? match : String(v);
  });
}

// SKILL.md invariant: never leave a {{PLACEHOLDER}} in generated output.
// Failing loudly here is the whole point — a silent placeholder ships a
// harness that lies about what it checks.
export function assertNoPlaceholders(text, label) {
  const left = [...text.matchAll(PLACEHOLDER)].map((m) => m[0]);
  if (left.length) {
    throw new Error(
      `${label}: unresolved placeholder(s) ${[...new Set(left)].join(', ')}`
    );
  }
}

export async function readTemplate(name) {
  return readFile(path.join(TEMPLATES_DIR, name), 'utf8');
}

export async function writeOut(target, relPath, contents, { force = false, dryRun = false } = {}) {
  const dest = path.join(target, relPath);
  if (existsSync(dest) && !force) {
    return { path: relPath, status: 'skipped', reason: 'exists' };
  }
  if (dryRun) return { path: relPath, status: 'would-write' };

  await mkdir(path.dirname(dest), { recursive: true });
  await writeFile(dest, contents, 'utf8');
  if (relPath.endsWith('.sh')) await chmod(dest, 0o755);
  return { path: relPath, status: 'written' };
}

// Two-stage rendering: a profile's verify block may itself contain {{probeKey}}
// tokens, which are resolved before the block is injected into verify.sh.
export function buildVerifyBlocks(profile, values, scripts) {
  const blocks = {};
  for (const mode of ['build', 'test', 'lint']) {
    const spec = profile.verify?.[mode];
    if (!spec) {
      blocks[mode] = `  echo "No ${mode} check configured for this project."`;
      continue;
    }
    const raw = typeof spec === 'string' ? spec : spec.block;
    // Never invent a check: if the profile says this step needs an npm script
    // and that script doesn't exist, say so instead of emitting a command
    // that will fail for everyone.
    if (typeof spec === 'object' && spec.requiresScript && !scripts[spec.requiresScript]) {
      blocks[mode] = `  echo "No ${mode} script in package.json — nothing to check."`;
      continue;
    }
    blocks[mode] = render(raw, values);
  }
  return blocks;
}
