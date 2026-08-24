// Plain Node project — CLI, library, or tooling with no web framework.
// Priority sits after web-react (20) and node-backend (30) so those match first;
// this is the catch-all for "it's Node, but not a server or a frontend".
export default {
  id: 'node-tool',
  name: 'Node tool / library (no framework)',
  priority: 40,

  detect: {
    files: ['package.json']
  },

  probe: {
    packageManager:
      "ls pnpm-lock.yaml >/dev/null 2>&1 && echo pnpm || (ls yarn.lock >/dev/null 2>&1 && echo yarn || (ls bun.lockb >/dev/null 2>&1 && echo bun || echo npm))",
    scriptsJson: "node -e \"try{console.log(JSON.stringify(require('./package.json').scripts||{}))}catch(e){console.log('{}')}\"",
    nodeVersion: 'node --version 2>/dev/null',
    isTypeScript: 'ls tsconfig.json 2>/dev/null'
  },

  verify: {
    build: { requiresScript: 'build', block: '  {{pmRun}} build || fail "build"' },
    test: { requiresScript: 'test', block: '  {{pmRun}} test || fail "test"' },
    lint: { requiresScript: 'lint', block: '  {{pmRun}} lint || fail "lint"' }
  },

  pitfalls: [
    'A CLI that exits 0 is not a CLI that worked. Assert on the output, not just the exit code.',
    'Keep runtime dependencies at zero where possible — every dependency is a thing users must install to run your tool.',
    'Scripts invoked by other tools must print a machine-parseable result line, not just human prose.'
  ],

  constitution: {
    architecture:
      '- Keep the CLI entry thin: parse arguments, call a library function, print the result.\n- Logic lives in `lib/` and stays testable without spawning a process.',
    platform: '- Node {{nodeVersion}}, package manager `{{packageManager}}`.',
    code:
      '- No `console.log` for control flow — return values, print once at the edge.\n- Fail loudly on bad input; never silently continue with a default that hides the problem.'
  },

  defaults: {
    baseBranch: 'main',
    branchPattern: 'feature/<topic>',
    featureIdExample: 'feat-042',
    techStack: 'Node {{nodeVersion}}, {{packageManager}}',
    structure: 'CLI entry points alongside a lib/ of testable modules.'
  }
};
