import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

// Files written by other harnesses (harness-creator, edts-harness) or by hand.
// Their presence is not a problem; silently generating alongside them is.
const LEGACY = [
  { file: 'feature_list.json', holds: 'features and evidence', goesTo: 'FEATURES.md + archive/features/' },
  { file: 'progress.md', holds: 'session history, decisions, lessons', goesTo: 'archive/sessions/ + JOURNAL.md + CONSTITUTION.md' },
  { file: 'claude-progress.md', holds: 'session history', goesTo: 'archive/sessions/' },
  { file: 'session-handoff.md', holds: 'current state and next step', goesTo: 'state/<name>.md' },
  { file: 'TASKS.md', holds: 'session task log', goesTo: 'FEATURES.md + archive/sessions/' },
  { file: 'init.sh', holds: 'verification commands', goesTo: 'verify.sh' },
  { file: 'clean-state-checklist.md', holds: 'definition of done', goesTo: 'AGENTS.md' },
  { file: 'quality-document.md', holds: 'quality bar', goesTo: 'CONSTITUTION.md' }
];

export async function detectLegacy(target) {
  const found = LEGACY.filter((l) => existsSync(path.join(target, l.file)));

  // The dangerous case: CLAUDE.md exists as a real instruction file rather than
  // a pointer. create would skip it, and an agent loading CLAUDE.md would follow
  // the OLD harness and never reach the new one.
  const claudePath = path.join(target, 'CLAUDE.md');
  let claudeConflict = null;
  if (existsSync(claudePath)) {
    const body = await readFile(claudePath, 'utf8');
    if (!/@AGENTS\.md/.test(body)) {
      claudeConflict = {
        lines: body.split(/\r?\n/).length,
        reason:
          'CLAUDE.md is a full instruction file, not a pointer. Generating alongside it leaves ' +
          'two competing harnesses, and an agent loading CLAUDE.md would follow the old one.'
      };
    }
  }

  return { found, claudeConflict, hasLegacy: found.length > 0 || claudeConflict !== null };
}

export function formatLegacyReport({ found, claudeConflict }) {
  const lines = [];
  if (claudeConflict) {
    lines.push('  CONFLICT  CLAUDE.md');
    lines.push(`            ${claudeConflict.lines} lines, no @AGENTS.md pointer.`);
    lines.push(`            ${claudeConflict.reason}`);
    lines.push('');
  }
  if (found.length) {
    lines.push('  Existing harness files detected:');
    for (const l of found) {
      lines.push(`    ${l.file.padEnd(24)} ${l.holds}`);
      lines.push(`    ${''.padEnd(24)} -> ${l.goesTo}`);
    }
    lines.push('');
  }
  return lines.join('\n');
}
