// iOS / Xcode. Probes for the real workspace, scheme and simulator so verify.sh
// works on the first run instead of shipping a guess that breaks for everyone.
export default {
  id: 'ios-xcode',
  name: 'iOS / Xcode (SwiftUI or UIKit)',
  priority: 10,

  detect: {
    globs: ['*.xcworkspace', '*.xcodeproj'],
    files: ['Package.swift']
  },

  probe: {
    workspace: "ls -d *.xcworkspace 2>/dev/null | head -1",
    project: "ls -d *.xcodeproj 2>/dev/null | head -1",
    // Slow on first run: Xcode resolves Swift packages before it will list schemes.
    schemesJson: { cmd: 'xcodebuild -list -json 2>/dev/null', timeout: 120_000 },
    simulatorsJson: "xcrun simctl list devices available --json 2>/dev/null",
    // The .xcodeproj is often nested (EDTSApp/EDTSApp.xcodeproj), so a root-level
    // glob silently finds nothing and loses the single most important platform
    // fact — the deployment target that decides which SwiftUI APIs compile.
    deploymentTarget:
      "find . -maxdepth 4 -name project.pbxproj -not -path './Pods/*' 2>/dev/null | head -1 | xargs grep -m1 -o 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*' 2>/dev/null | head -1"
  },

  verify: {
    build: [
      '  xcodebuild -workspace "{{workspace}}" -scheme "{{scheme}}" \\',
      '    -destination "{{destination}}" build \\',
      '    | tee /tmp/verify_build.log | tail -20',
      '  grep -q "BUILD SUCCEEDED" /tmp/verify_build.log || fail "build"'
    ].join('\n'),
    test: [
      '  xcodebuild -workspace "{{workspace}}" -scheme "{{scheme}}" \\',
      '    -destination "{{destination}}" test \\',
      '    | tee /tmp/verify_test.log | tail -40',
      '  grep -q "TEST SUCCEEDED" /tmp/verify_test.log || fail "test"'
    ].join('\n')
  },

  // Real lessons. Each of these cost a debugging session the first time.
  pitfalls: [
    "Pipe xcodebuild through `tee` + `grep 'BUILD SUCCEEDED'`. Piping to `tail` alone hides failures, because `set -e` only sees tail's exit code, not xcodebuild's.",
    'Check the real IPHONEOS_DEPLOYMENT_TARGET before using newer SwiftUI APIs. `@FocusState` is iOS 15+, `.onChange(of:perform:)` is 14+ — both fail to build on 13.',
    'Never open the `.xcodeproj` directly when a `.xcworkspace` exists.',
    'A new test file compiles but is silently NOT RUN unless it has test-target membership. Confirm the test count actually increased, not just that the suite passed.'
  ],

  constitution: {
    architecture:
      '- Define the layer chain and make it mandatory (e.g. View → ViewModel → UseCase →\n  Repository → Service). Views never skip layers.',
    platform:
      '- **Deployment target: {{deploymentTarget}}.** Check API availability before using any\n  newer SwiftUI/UIKit API.\n- **Workspace only:** build via `{{workspace}}`, never the `.xcodeproj` directly.',
    code:
      '- No `print()` — use OSLog if logging is genuinely needed.\n- No force unwraps (`!`), force casts (`as!`), or `try!` in app code. Test mocks excepted.\n- Never weaken ATS / `NSAllowsArbitraryLoads` in any Info.plist.'
  },

  defaults: {
    baseBranch: 'develop',
    branchPattern: 'feature-<topic>/<detail>',
    featureIdExample: 'feat-042',
    techStack: 'Swift / Xcode. {{deploymentTarget}}',
    structure: 'App target plus local Swift packages. Shared code in a Core module.'
  }
};
