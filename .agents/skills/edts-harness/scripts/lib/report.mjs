import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const TEMPLATE = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  'templates',
  'audit-report.html'
);

// The report renders untrusted repo content (file names, parsed table cells),
// so everything interpolated is escaped.
function esc(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function pct(cat) {
  const passed = cat.checks.filter((c) => c.pass).length;
  return { passed, total: cat.checks.length, pct: Math.round((passed / cat.checks.length) * 100) };
}

function categoryCards(categories) {
  return categories
    .map((cat) => {
      const { passed, total, pct: p } = pct(cat);
      return `  <div class="cat">
    <div class="n">${esc(cat.name)}</div>
    <div class="v">${passed}/${total} checks · ${p}%</div>
    <div class="bar"><i style="width:${p}%"></i></div>
  </div>`;
    })
    .join('\n');
}

function checkSections(categories) {
  return categories
    .map((cat) => {
      const { passed, total } = pct(cat);
      const rows = cat.checks
        .map((c) => {
          const cls = c.pass ? 'p' : c.severity === 'warn' ? 'w' : 'f';
          const word = c.pass
            ? 'PASS'
            : c.severity === 'warn'
              ? 'WARN'
              : c.severity === 'critical'
                ? 'CRITICAL'
                : 'FAIL';
          const fix = c.pass ? '' : `<div class="fix"><b>fix:</b> ${esc(c.fix)}</div>`;
          return `      <tr>
        <td class="s ${cls}">${word}</td>
        <td>${esc(c.label)}
          <div class="detail">${esc(c.detail)}</div>${fix}
        </td>
      </tr>`;
        })
        .join('\n');
      return `<h2>${esc(cat.name)} — ${passed}/${total}</h2>
<table>
  <thead><tr><th>Result</th><th>Check</th></tr></thead>
  <tbody>
${rows}
  </tbody>
</table>`;
    })
    .join('\n\n');
}

export async function renderHtmlReport({ project, overall, label, categories, generated }) {
  const tpl = await readFile(TEMPLATE, 'utf8');
  return tpl
    .replace(/\{\{PROJECT\}\}/g, esc(project))
    .replace(/\{\{SCORE\}\}/g, String(overall))
    .replace(/\{\{LABEL\}\}/g, esc(label))
    .replace(/\{\{GENERATED\}\}/g, esc(generated))
    .replace('{{CATEGORY_CARDS}}', categoryCards(categories))
    .replace('{{CHECK_SECTIONS}}', checkSections(categories));
}
