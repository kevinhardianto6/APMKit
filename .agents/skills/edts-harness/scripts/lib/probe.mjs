import { execSync } from 'node:child_process';

// Probes are read-only, best-effort discovery. A probe that fails returns null
// rather than aborting: a missing Xcode or an unreadable package.json should
// degrade the output, not stop the harness from being created.
export function runProbe(command, cwd, timeout = 20_000) {
  try {
    const out = execSync(command, {
      cwd,
      timeout,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      shell: '/bin/bash'
    });
    const trimmed = out.trim();
    return trimmed.length ? trimmed : null;
  } catch {
    return null;
  }
}

// A probe may be a plain command string, or { cmd, timeout } when it is known
// to be slow — `xcodebuild -list` can take over a minute while SPM resolves.
export function runProbes(profile, cwd) {
  const results = {};
  for (const [key, spec] of Object.entries(profile.probe ?? {})) {
    const cmd = typeof spec === 'string' ? spec : spec.cmd;
    const timeout = typeof spec === 'string' ? undefined : spec.timeout;
    results[key] = runProbe(cmd, cwd, timeout ?? 20_000);
  }
  return results;
}

// git config user.name can contain spaces and capitals ("Jovanes Jovanotti").
// State files are addressed by a filesystem-safe slug of it.
export function slugifyUser(name) {
  return (name ?? 'unknown')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'unknown';
}

export function gitUser(cwd) {
  return runProbe('git config user.name', cwd, 5000);
}

// Pull the first scheme out of `xcodebuild -list -json`. Prefers a name
// containing "dev" — most iOS repos have dev/staging/prod and dev is the
// right default for local verification.
export function pickScheme(schemesJson) {
  if (!schemesJson) return null;
  try {
    const parsed = JSON.parse(schemesJson);
    const schemes = parsed.workspace?.schemes ?? parsed.project?.schemes ?? [];
    if (!schemes.length) return null;
    return schemes.find((s) => /dev/i.test(s)) ?? schemes[0];
  } catch {
    return null;
  }
}

// Pick a real installed simulator instead of hardcoding a device name that
// disappears with the next Xcode release.
export function pickSimulator(simulatorsJson) {
  if (!simulatorsJson) return null;
  try {
    const { devices } = JSON.parse(simulatorsJson);
    const runtimes = Object.keys(devices ?? {})
      .filter((k) => /iOS/i.test(k))
      .sort()
      .reverse(); // newest runtime first
    for (const runtime of runtimes) {
      const available = (devices[runtime] ?? []).filter((d) => d.isAvailable);
      const preferred =
        available.find((d) => /iPhone \d+ Pro$/.test(d.name)) ??
        available.find((d) => /iPhone/.test(d.name)) ??
        available[0];
      if (preferred) return preferred.name;
    }
    return null;
  } catch {
    return null;
  }
}

export function parseScripts(scriptsJson) {
  if (!scriptsJson) return {};
  try {
    return JSON.parse(scriptsJson);
  } catch {
    return {};
  }
}
