// Python. The verify block deliberately tolerates pytest's exit code 5
// ("no tests collected") — a repo that hasn't written tests yet should not fail
// its build for the wrong reason.
export default {
  id: 'python',
  name: 'Python (pytest)',
  priority: 50,

  detect: {
    files: ['pyproject.toml', 'requirements.txt', 'setup.py', 'setup.cfg']
  },

  probe: {
    python: 'command -v python3 >/dev/null && python3 --version 2>&1',
    manager:
      "ls uv.lock >/dev/null 2>&1 && echo uv || (ls poetry.lock >/dev/null 2>&1 && echo poetry || echo pip)",
    hasPytest: "grep -rl 'pytest' pyproject.toml requirements.txt setup.cfg 2>/dev/null | head -1",
    hasRuff: "grep -rl 'ruff' pyproject.toml requirements.txt 2>/dev/null | head -1",
    venv: 'ls -d .venv venv 2>/dev/null | head -1'
  },

  verify: {
    build: [
      '  # Syntax check. -q keeps it quiet; exclusions stop it walking dependencies.',
      '  python3 -m compileall -q -x "(\\.venv|venv|build|dist|node_modules)" . || fail "build"'
    ].join('\n'),
    test: [
      '  # pytest exits 5 when it collects zero tests. Under `set -e` that reads as a',
      '  # failure, so a repo with no tests yet would fail for the wrong reason.',
      '  python3 -m pytest -q; code=$?',
      '  if [ $code -ne 0 ] && [ $code -ne 5 ]; then fail "test"; fi',
      '  [ $code -eq 5 ] && echo "pytest collected no tests."'
    ].join('\n')
  },

  pitfalls: [
    'pytest exits 5 when it collects zero tests. Under `set -e` that looks like a failure — a repo with no tests yet breaks its own build for the wrong reason.',
    'There is often no bare `python` on modern systems, only `python3`. A script that says `python` works on your machine and fails in CI.',
    'Running pytest outside the virtualenv silently resolves system packages, so it can pass or fail for reasons unrelated to the change.',
    '`compileall` walks into `.venv`, `build` and `dist` unless excluded, and then reports syntax errors from dependencies as if they were yours.'
  ],

  constitution: {
    architecture:
      '- Keep IO at the edges: pure functions in the core, side effects in thin adapters.\n- Modules do not import each other in a cycle; if they must, the boundary is wrong.',
    platform:
      '- Python: {{python}} · dependency manager: `{{manager}}`.\n- Always work inside the virtualenv — a green run outside it proves nothing.',
    code:
      '- No bare `except:` — catch the exception you actually expect.\n- No mutable default arguments.\n- Type hints on public functions; they are the cheapest documentation that cannot go stale.'
  },

  defaults: {
    baseBranch: 'main',
    branchPattern: 'feature/<topic>',
    featureIdExample: 'feat-042',
    techStack: '{{python}}, {{manager}}',
    structure: 'Package under src/ or the project name, tests mirroring it under tests/.'
  }
};
