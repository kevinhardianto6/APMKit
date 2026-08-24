// Flutter. Priority sits above android-gradle so a Flutter app matches here
// rather than on its own android/ subproject.
export default {
  id: 'flutter',
  name: 'Flutter / Dart',
  priority: 15,

  detect: {
    files: ['pubspec.yaml']
  },

  probe: {
    flutterVersion: "flutter --version 2>/dev/null | head -1",
    dartSdk: "grep -A2 'environment:' pubspec.yaml 2>/dev/null | grep sdk | head -1",
    devices: 'flutter devices --machine 2>/dev/null | head -40',
    hasTests: 'ls -d test 2>/dev/null'
  },

  verify: {
    build: [
      '  # analyze exits 0 when only "info" issues exist, so grep the output too.',
      '  flutter analyze 2>&1 | tee /tmp/verify_analyze.log',
      '  grep -qE "error •" /tmp/verify_analyze.log && fail "analyze"',
      '  true'
    ].join('\n'),
    test: '  flutter test || fail "test"'
  },

  pitfalls: [
    '`flutter analyze` exits 0 when every issue is severity "info". A clean exit code does not mean a clean analysis — grep the output for "error •".',
    'Hot reload does not re-run `main()` or `initState`. A change that appears not to work may simply not have been applied; full restart before concluding anything.',
    'Widget tests pass against a fake 800x600 surface. Layout that overflows on a real phone is invisible to `flutter test`.',
    '`pubspec.lock` belongs in version control for applications and out of it for published packages. Getting this backwards produces builds nobody can reproduce.'
  ],

  constitution: {
    architecture:
      '- Widgets render; they do not fetch, cache or hold business logic.\n- State management is one pattern across the app, not per-screen preference.',
    platform: '- Flutter toolchain: {{flutterVersion}}.\n- If that reads "not detected", record the version the team actually builds with.',
    code:
      '- No `print()` — use a logger that can be silenced in release.\n- No `!` null assertion without a comment proving it cannot be null.\n- `const` constructors wherever possible; they are free rebuild avoidance.'
  },

  defaults: {
    baseBranch: 'main',
    branchPattern: 'feature/<topic>',
    featureIdExample: 'feat-042',
    techStack: '{{flutterVersion}}',
    structure: 'lib/ by feature, shared widgets and services alongside; tests mirror lib/ under test/.'
  }
};
