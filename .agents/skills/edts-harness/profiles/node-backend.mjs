// Node backend (Express / Fastify / Nest). Lower priority than web-react so a
// React app with a server dependency still matches the frontend profile first.
export default {
  id: 'node-backend',
  name: 'Node backend (Express / Fastify / Nest)',
  priority: 30,

  detect: {
    files: ['package.json'],
    packageDeps: ['express', 'fastify', '@nestjs/core', 'koa', 'hapi']
  },

  probe: {
    packageManager:
      "ls pnpm-lock.yaml >/dev/null 2>&1 && echo pnpm || (ls yarn.lock >/dev/null 2>&1 && echo yarn || (ls bun.lockb >/dev/null 2>&1 && echo bun || echo npm))",
    scriptsJson: "node -e \"try{console.log(JSON.stringify(require('./package.json').scripts||{}))}catch(e){console.log('{}')}\"",
    nodeVersion: 'node --version 2>/dev/null',
    hasDocker: 'ls docker-compose.yml docker-compose.yaml 2>/dev/null | head -1'
  },

  verify: {
    build: { requiresScript: 'build', block: '  {{pmRun}} build || fail "build"' },
    test: { requiresScript: 'test', block: '  {{pmRun}} test || fail "test"' },
    lint: { requiresScript: 'lint', block: '  {{pmRun}} lint || fail "lint"' }
  },

  pitfalls: [
    'A green unit suite is not a working endpoint. Exercise the route before claiming done.',
    'Migrations are not optional state — a schema change without a migration breaks every other machine.',
    'Never log request bodies or tokens; they end up in aggregated logs.'
  ],

  constitution: {
    architecture:
      '- Route → service → repository. Routes contain no business logic and no direct DB access.\n- One module owns one concern; modules do not import each other sideways.',
    platform: '- Node {{nodeVersion}}, package manager `{{packageManager}}`.',
    code:
      '- No secrets in code or committed `.env` files — configuration comes from the environment.\n- No unhandled promise rejections; every async path has an error branch.\n- No `console.log` in committed code; use the project logger.'
  },

  defaults: {
    baseBranch: 'main',
    branchPattern: 'feature/<topic>',
    featureIdExample: 'feat-042',
    techStack: 'Node backend, {{packageManager}}, Node {{nodeVersion}}',
    structure: 'Routes, services and repositories in separate layers under src/.'
  }
};
