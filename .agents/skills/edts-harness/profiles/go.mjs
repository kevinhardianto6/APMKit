// Go. `go vet` is included in the build step because it catches real bugs the
// compiler accepts, and it costs almost nothing to run.
export default {
  id: 'go',
  name: 'Go',
  priority: 60,

  detect: {
    files: ['go.mod']
  },

  probe: {
    goVersion: 'go version 2>/dev/null',
    module: "head -1 go.mod 2>/dev/null | awk '{print $2}'",
    hasTests: "find . -name '*_test.go' -not -path './vendor/*' 2>/dev/null | head -1"
  },

  verify: {
    build: [
      '  go build ./... || fail "build"',
      '  # vet catches printf mismatches, lost struct tags and unreachable code that',
      '  # the compiler happily accepts.',
      '  go vet ./... || fail "vet"'
    ].join('\n'),
    test: '  go test ./... || fail "test"'
  },

  pitfalls: [
    '`go test ./...` prints "ok ... [no test files]" and exits 0 for packages with no tests. Full coverage and zero coverage look identical in the output — read it, do not just check the exit code.',
    '`go vet` finds bugs `go build` allows (printf argument mismatches, misused struct tags). Skipping it is skipping free correctness checks.',
    'Build tags silently exclude files from both build and test. A file you think is covered may not even be compiled.',
    'A nil map reads fine and panics on write. The zero value is usable for reads only.'
  ],

  constitution: {
    architecture:
      '- Accept interfaces, return structs.\n- Package boundaries follow domain, not layer — no `utils` package.',
    platform: '- Go: {{goVersion}} · module `{{module}}`.\n- If either reads "not detected", fill it in — CI will not guess for you.',
    code:
      '- Every error is handled or explicitly ignored with `_` and a reason; never dropped silently.\n- No `panic` in library code — return an error and let the caller decide.\n- Context is the first parameter on anything that does IO.'
  },

  defaults: {
    baseBranch: 'main',
    branchPattern: 'feature/<topic>',
    featureIdExample: 'feat-042',
    techStack: '{{goVersion}}',
    structure: 'cmd/ for entry points, internal/ for private packages, pkg/ only if genuinely shared.'
  }
};
