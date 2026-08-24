import { readFile, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

export const STATUS = {
  '🟡': 'not started',
  '🔵': 'in progress',
  '✅': 'done',
  '🔴': 'blocked',
  '🟠': 'needs verification'
};

export const PLACEHOLDER = /\{\{[A-Za-z0-9_]+\}\}/g;

export async function readIfExists(p) {
  return existsSync(p) ? readFile(p, 'utf8') : null;
}

// Split markdown into sections keyed by heading, keeping the level so we can
// tell an epic (##) from a feature detail (###).
export function splitSections(md) {
  if (!md) return [];
  const sections = [];
  let current = null;
  for (const line of md.split(/\r?\n/)) {
    const m = /^(#{1,6})\s+(.*)$/.exec(line);
    if (m) {
      current = { level: m[1].length, heading: m[2].trim(), body: [] };
      sections.push(current);
    } else if (current) {
      current.body.push(line);
    }
  }
  return sections.map((s) => ({ ...s, body: s.body.join('\n') }));
}

export function hasSection(md, name) {
  return splitSections(md).some((s) => new RegExp(name, 'i').test(s.heading));
}

// Parse every markdown table in a block into { header, rows } where each row is
// an array of trimmed cells.
export function parseTables(body) {
  if (!body) return [];
  const tables = [];
  let current = null;
  for (const line of body.split(/\r?\n/)) {
    const t = line.trim();
    if (t.startsWith('|') && t.endsWith('|')) {
      const cells = t.slice(1, -1).split('|').map((c) => c.trim());
      if (/^:?-+:?$/.test(cells[0])) continue; // separator row (:-: is valid too)
      if (!current) {
        current = { header: cells, rows: [] };
        tables.push(current);
      } else {
        current.rows.push(cells);
      }
    } else if (t === '') {
      current = null;
    }
  }
  return tables;
}

function statusOf(cell) {
  const found = Object.keys(STATUS).find((sym) => cell.includes(sym));
  return found ?? null;
}

function splitDeps(cell) {
  if (!cell || /^[—\-–]$/.test(cell.trim())) return [];
  return cell
    .split(',')
    .map((s) => s.replace(/`/g, '').trim())
    .filter((s) => s && !/^[—\-–]$/.test(s));
}

// Model of FEATURES.md: epics with their summary rows, plus any inline
// feature-detail sections and their evidence tables.
export function parseFeatures(md) {
  const sections = splitSections(md);
  const epics = [];
  const details = [];

  for (const s of sections) {
    if (s.level === 2 && /^Epic\b/i.test(s.heading)) {
      const tables = parseTables(s.body);
      const summary = tables.find((t) => t.header.some((h) => /^ID$/i.test(h)));
      const rows = (summary?.rows ?? [])
        .map((cells) => {
          const col = (name) => {
            const i = summary.header.findIndex((h) => new RegExp(`^${name}$`, 'i').test(h));
            return i >= 0 ? cells[i] ?? '' : '';
          };
          const id = col('ID').replace(/`/g, '').trim();
          if (!id) return null;
          return {
            id,
            name: col('Feature'),
            status: statusOf(col('Status')),
            by: col('By'),
            dependsOn: splitDeps(col('Depends on')),
            evidence: col('Evidence')
          };
        })
        .filter(Boolean);

      epics.push({
        name: s.heading.replace(/^Epic\s*[·:-]\s*/i, '').trim(),
        body: s.body,
        prd: /\*\*PRD:\*\*\s*(\S+)/.exec(s.body)?.[1] ?? null,
        started: /\*\*Started:\*\*\s*([0-9-]+)/.exec(s.body)?.[1] ?? null,
        startedBy: /\*\*Started by:\*\*\s*(\S+)/.exec(s.body)?.[1] ?? null,
        rows
      });
    }

    if (s.level === 3) {
      const id = /^([A-Za-z][A-Za-z0-9]*-?\d+)/.exec(s.heading.replace(/`/g, ''))?.[1];
      if (!id) continue;
      const evidence = parseTables(s.body).find((t) =>
        t.header.some((h) => /check/i.test(h))
      );
      details.push({
        id,
        heading: s.heading,
        evidenceRows: evidence?.rows ?? [],
        body: s.body
      });
    }
  }

  return { epics, details, allRows: epics.flatMap((e) => e.rows) };
}

// Returns the list of dependency cycles, each as the ids involved.
export function findCycles(rows) {
  const byId = new Map(rows.map((r) => [r.id, r]));
  const cycles = [];
  const state = new Map(); // id -> 'visiting' | 'done'

  const walk = (id, trail) => {
    if (state.get(id) === 'done') return;
    if (state.get(id) === 'visiting') {
      const start = trail.indexOf(id);
      if (start >= 0) cycles.push(trail.slice(start).concat(id));
      return;
    }
    state.set(id, 'visiting');
    for (const dep of byId.get(id)?.dependsOn ?? []) {
      if (byId.has(dep)) walk(dep, trail.concat(id));
    }
    state.set(id, 'done');
  };

  for (const r of rows) walk(r.id, []);
  return cycles;
}

export async function listStateFiles(target) {
  const dir = path.join(target, 'state');
  if (!existsSync(dir)) return [];
  const files = (await readdir(dir)).filter((f) => f.endsWith('.md'));
  return Promise.all(
    files.map(async (f) => ({
      name: f,
      rel: path.join('state', f),
      content: await readFile(path.join(dir, f), 'utf8')
    }))
  );
}

export function lineCount(text) {
  return text ? text.split(/\r?\n/).length : 0;
}
