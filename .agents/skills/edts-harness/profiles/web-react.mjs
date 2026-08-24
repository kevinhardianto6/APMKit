// React / frontend web. Verify steps are gated on scripts that actually exist in
// package.json — never invent a lint or test step the project hasn't configured.
export default {
  id: 'web-react',
  name: 'Web frontend (React / Vite / Next)',
  priority: 20,

  detect: {
    files: ['package.json'],
    packageDeps: ['react', 'next', 'vite']
  },

  probe: {
    packageManager:
      "ls pnpm-lock.yaml >/dev/null 2>&1 && echo pnpm || (ls yarn.lock >/dev/null 2>&1 && echo yarn || (ls bun.lockb >/dev/null 2>&1 && echo bun || echo npm))",
    scriptsJson: "node -e \"try{console.log(JSON.stringify(require('./package.json').scripts||{}))}catch(e){console.log('{}')}\"",
    nodeVersion: 'node --version 2>/dev/null'
  },

  verify: {
    build: { requiresScript: 'build', block: '  {{pmRun}} build || fail "build"' },
    test: { requiresScript: 'test', block: '  {{pmRun}} test || fail "test"' },
    lint: { requiresScript: 'lint', block: '  {{pmRun}} lint || fail "lint"' }
  },

  pitfalls: [
    'Only list scripts that exist in package.json. A verify step that cannot run is worse than no step.',
    'Lockfile decides the package manager — do not mix npm and pnpm in one repo.',
    'A passing build is not a passing render. Exercise the affected screen before claiming done.'
  ],

  constitution: {
    architecture:
      '- Keep data fetching out of presentational components.\n- Shared UI lives in one place; feature folders never import each other directly.',
    platform:
      '- Node {{nodeVersion}}, package manager `{{packageManager}}` (decided by the lockfile).',
    code:
      '- No `console.log` left in committed code.\n- No `any` in TypeScript without a written reason.\n- No secrets in client-side code or committed `.env` files.'
  },

  defaults: {
    baseBranch: 'main',
    branchPattern: 'feature/<topic>',
    featureIdExample: 'feat-042',
    techStack: 'React frontend, {{packageManager}}, Node {{nodeVersion}}',
    structure: 'Feature folders under src/, shared UI and utilities alongside.'
  }
};
