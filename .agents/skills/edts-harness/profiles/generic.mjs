// Fallback when no stack matches. Emits an explicitly TODO-marked verify.sh rather
// than a silent placeholder, so the gap is visible instead of quietly passing.
export default {
  id: 'generic',
  name: 'Generic (stack not detected)',
  priority: 999,

  detect: {},

  probe: {},

  verify: {
    build: {
      block:
        '  echo "TODO: replace with this project\'s real build command." >&2\n  fail "build not configured"'
    }
  },

  pitfalls: [
    'verify.sh is not configured yet. Fill in the real build/test commands before trusting any ✅.'
  ],

  constitution: {
    architecture: '- Describe the layering this project actually uses, and make it mandatory.',
    platform: '- Record the runtime/toolchain versions this project requires.',
    code: '- List the prohibitions that matter here (logging, secrets, unsafe casts).'
  },

  defaults: {
    baseBranch: 'main',
    branchPattern: 'feature/<topic>',
    featureIdExample: 'feat-042',
    techStack: 'Not detected — fill this in.',
    structure: 'Not detected — fill this in.'
  }
};
