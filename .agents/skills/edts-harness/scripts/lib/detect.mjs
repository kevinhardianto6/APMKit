import { readdir, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const PROFILES_DIR = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  'profiles'
);

export async function loadProfiles(dir = PROFILES_DIR) {
  const files = (await readdir(dir)).filter((f) => f.endsWith('.mjs'));
  const profiles = [];
  for (const file of files) {
    const mod = await import(pathToFileURL(path.join(dir, file)).href);
    if (mod.default?.id) profiles.push(mod.default);
  }
  // Lower priority number wins, so the most specific profile matches first.
  return profiles.sort((a, b) => (a.priority ?? 500) - (b.priority ?? 500));
}

async function packageDeps(target) {
  const pkgPath = path.join(target, 'package.json');
  if (!existsSync(pkgPath)) return null;
  try {
    const pkg = JSON.parse(await readFile(pkgPath, 'utf8'));
    return { ...pkg.dependencies, ...pkg.devDependencies };
  } catch {
    return null; // malformed package.json shouldn't crash detection
  }
}

// Only supports the "*.ext" form — that's all profiles need, and a full glob
// implementation would be a dependency we don't want.
async function matchesGlob(target, pattern) {
  if (!pattern.startsWith('*.')) return existsSync(path.join(target, pattern));
  const ext = pattern.slice(1);
  try {
    return (await readdir(target)).some((f) => f.endsWith(ext));
  } catch {
    return false;
  }
}

export async function detectStack(target, profiles) {
  const deps = await packageDeps(target);

  for (const profile of profiles) {
    const d = profile.detect;
    if (!d || Object.keys(d).length === 0) continue; // generic has no rules

    // A profile that names packageDeps must match one of them. This is what
    // keeps a React app from matching node-backend just because both have
    // a package.json.
    if (d.packageDeps?.length) {
      if (!deps) continue;
      if (!d.packageDeps.some((name) => name in deps)) continue;
    }

    let hit = false;
    for (const file of d.files ?? []) {
      if (existsSync(path.join(target, file))) hit = true;
    }
    for (const glob of d.globs ?? []) {
      if (await matchesGlob(target, glob)) hit = true;
    }
    if (d.packageDeps?.length && !d.files?.length && !d.globs?.length) hit = true;

    if (hit) return profile;
  }

  return profiles.find((p) => p.id === 'generic') ?? null;
}
