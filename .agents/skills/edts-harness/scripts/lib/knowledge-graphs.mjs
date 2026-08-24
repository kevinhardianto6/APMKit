import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

// The four skills code-review-graph ships. Only the ones actually present get
// recommended — pointing an agent at a skill that isn't installed is the same
// class of bug as documenting a tool that isn't installed.
const CRG_SKILLS = ['debug-issue', 'explore-codebase', 'refactor-safely', 'review-changes'];

// Detects whether graphify and/or code-review-graph are already installed in
// a target repo, so AGENTS.md can document them when present and stay silent
// when absent — no dangling references to tools a project doesn't use.
//
// Detection is deliberately OR-based (any one signal means "installed"), so the
// returned object also reports *which* signals fired. The prose builders below
// claim only what was actually observed: a repo can have `graphify-out/` with no
// hooks, or an `.mcp.json` entry with no auto-update wiring, and telling the
// agent otherwise makes it trust a stale graph.
export function detectKnowledgeGraphs(target) {
  const read = (rel) => {
    try { return readFileSync(path.join(target, rel), 'utf8'); } catch { return null; }
  };

  const postCommit = read(path.join('.git', 'hooks', 'post-commit'));
  const preCommit = read(path.join('.git', 'hooks', 'pre-commit'));
  const mcpJson = read('.mcp.json');
  const gitignore = read('.gitignore') || '';
  const claudeSettings = read(path.join('.claude', 'settings.json'));

  const graphifyHook = Boolean(postCommit && postCommit.includes('graphify-hook-start'));
  const crgPreCommit = Boolean(preCommit && preCommit.includes('Installed by code-review-graph'));

  const graphify = Boolean(existsSync(path.join(target, 'graphify-out')) || graphifyHook);

  const codeReviewGraph = Boolean(
    existsSync(path.join(target, '.code-review-graph')) ||
    crgPreCommit ||
    (mcpJson && mcpJson.includes('code-review-graph'))
  );

  return {
    graphify,
    codeReviewGraph,
    graphifyHook,
    graphifyIgnored: hasIgnoreRule(gitignore, 'graphify-out'),
    crgPreCommit,
    crgPostToolUse: hasPostToolUseHook(claudeSettings),
    crgSkills: CRG_SKILLS.filter((s) =>
      existsSync(path.join(target, '.claude', 'skills', s, 'SKILL.md'))
    )
  };
}

// A `.gitignore` entry, allowing the usual `dir`, `dir/`, `/dir` spellings and
// trailing whitespace. Commented-out lines don't count.
function hasIgnoreRule(gitignore, entry) {
  return gitignore
    .split('\n')
    .some((line) => {
      const t = line.trim();
      if (!t || t.startsWith('#')) return false;
      return t.replace(/^\//, '').replace(/\/$/, '') === entry;
    });
}

// True only when `.claude/settings.json` really wires code-review-graph into a
// PostToolUse hook. Unreadable or malformed settings count as "no hook" — the
// conservative direction, since the whole point is to avoid over-claiming.
function hasPostToolUseHook(raw) {
  if (!raw) return false;
  let parsed;
  try { parsed = JSON.parse(raw); } catch { return false; }
  const entries = parsed?.hooks?.PostToolUse;
  if (!Array.isArray(entries)) return false;
  return entries.some((entry) =>
    Array.isArray(entry?.hooks) &&
    entry.hooks.some((h) => typeof h?.command === 'string' && h.command.includes('code-review-graph'))
  );
}

function codeReviewGraphBlock({ crgPostToolUse, crgPreCommit, crgSkills }) {
  let freshness;
  if (crgPostToolUse && crgPreCommit) {
    freshness = `Tree-sitter-native; auto-updates on every Edit/Write via a \`PostToolUse\` hook and on commit
  via a pre-commit hook (see \`.claude/settings.json\` / \`.git/hooks/pre-commit\`) — cheapest in
  tokens for pure code questions, no manual re-sync needed.`;
  } else if (crgPostToolUse) {
    freshness = `Tree-sitter-native; auto-updates on every Edit/Write via a \`PostToolUse\` hook
  (\`.claude/settings.json\`). No pre-commit hook is installed, so a commit made outside this
  agent does not refresh the index.`;
  } else if (crgPreCommit) {
    freshness = `Tree-sitter-native; refreshes on commit via a pre-commit hook
  (\`.git/hooks/pre-commit\`). No \`PostToolUse\` hook is installed, so edits made during a
  session are not indexed until you commit.`;
  } else {
    freshness = `Tree-sitter-native, but **no auto-update hook was detected** — the index does not
  refresh itself. Re-sync with \`code-review-graph update\` after changing code, and treat its
  answers as suspect until you do: a stale index is confidently wrong, which is worse than no
  index at all.`;
  }

  const skillsLine = crgSkills.length
    ? `
  - Prefer the packaged skills over raw tool calls when the task matches one:
    ${crgSkills.map((s) => `\`${s}\``).join(', ')} (\`.claude/skills/\`) — they chain the
    right tools in the right order.`
    : '';

  return `- **code-review-graph (MCP tools)** — use FIRST for anything about the code itself: how a
  function/class works, who calls what, blast radius of a change, test coverage, dead code.
  ${freshness}
  - \`semantic_search_nodes_tool\` / \`query_graph_tool\` instead of Grep to find code
  - \`get_impact_radius_tool\` / \`get_affected_flows_tool\` instead of manually tracing imports
  - \`detect_changes_tool\` + \`get_review_context_tool\` for reviewing a diff
  - \`get_architecture_overview_tool\` / \`list_communities_tool\` for structural overview
  - \`refactor_tool\` for rename planning / dead code${skillsLine}`;
}

function graphifyBlock(target, tier, { graphifyHook, graphifyIgnored }) {
  const docs = ['CONSTITUTION.md'];
  if (tier !== 'lite') docs.push('FEATURES.md');
  if (tier === 'full') docs.push('JOURNAL.md');
  if (tier !== 'lite') docs.push('archive/');
  if (existsSync(path.join(target, 'README.md'))) docs.push('the README');

  const docList = docs.length > 1
    ? `${docs.slice(0, -1).join(', ')}, and ${docs[docs.length - 1]}`
    : docs[0];

  const manualDocs = docs.filter((d) => d !== 'the README').join(', ');

  const freshness = graphifyHook
    ? `- Auto-rebuilds on \`git commit\` / \`git checkout\` via installed hooks (\`graphify hook status\`
    to check). Doc-only changes (editing ${manualDocs}) still need a manual \`graphify update .\`.`
    : `- **No graphify git hooks were detected** — the graph does not rebuild itself. Run
    \`graphify update .\` after changing code or docs, or install the hooks and confirm with
    \`graphify hook status\`. Until then, check the date on \`graphify-out/\` before trusting an
    answer: a stale graph is confidently wrong.`;

  const ignoreLine = graphifyIgnored
    ? `- \`graphify-out/\` is gitignored (regenerable build artifact, not committed).`
    : `- \`graphify-out/\` is **not** in \`.gitignore\` — add it. It is a regenerable build artifact
    and committing it puts a large, always-conflicting file into every diff.`;

  return `- **graphify** (\`graphify query "<question>"\`, \`graphify path "<A>" "<B>"\`,
  \`graphify explain "<concept>"\`) — use for questions that span code AND docs: why a decision
  was made, what rule in \`CONSTITUTION.md\` covers a case, how an archived feature relates to
  current code. It ingested ${docList} alongside the code — code-review-graph did not.
  - Read \`graphify-out/GRAPH_REPORT.md\` only for broad architecture review, or when
    query/path/explain don't surface enough context.
  ${freshness}
  ${ignoreLine}`;
}

// Returns the full "## Knowledge graphs" section (with leading/trailing blank
// lines) when at least one tool is detected, or '' when neither is — the
// AGENTS.md.template placeholder collapses to nothing rather than leaving a
// dangling heading for tools the project doesn't have.
export function buildKnowledgeGraphsSection(detected, target, tier) {
  const { graphify, codeReviewGraph } = detected;
  if (!graphify && !codeReviewGraph) return '';

  const bullets = [];
  if (codeReviewGraph) bullets.push(codeReviewGraphBlock(detected));
  if (graphify) bullets.push(graphifyBlock(target, tier, detected));

  const intro = graphify && codeReviewGraph
    ? 'Two graph tools are installed. They are scoped to different questions — don\'t use them\ninterchangeably.'
    : `${codeReviewGraph ? 'code-review-graph' : 'graphify'} is installed for token-efficient codebase exploration.`;

  const fallback = graphify && codeReviewGraph
    ? 'Fall back to Grep/Glob/Read only when neither graph covers what you need.'
    : `Fall back to Grep/Glob/Read only when ${codeReviewGraph ? 'code-review-graph' : 'graphify'} doesn't cover what you need.`;

  return `## Knowledge graphs

${intro}

${bullets.join('\n')}

${fallback}

`;
}
