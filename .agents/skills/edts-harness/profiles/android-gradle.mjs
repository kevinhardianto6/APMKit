// Android / Gradle. Always drives the wrapper, never a system gradle — the
// wrapper pins the version the project actually builds with.
export default {
  id: 'android-gradle',
  name: 'Android (Gradle)',
  priority: 18,

  detect: {
    files: ['settings.gradle', 'settings.gradle.kts', 'build.gradle', 'build.gradle.kts']
  },

  probe: {
    gradleWrapper: 'ls gradlew 2>/dev/null',
    gradleVersion:
      "grep -o 'gradle-[0-9.]*' gradle/wrapper/gradle-wrapper.properties 2>/dev/null | head -1",
    javaVersion: 'java -version 2>&1 | head -1',
    compileSdk: "grep -rhoE 'compileSdk[a-zA-Z]* [0-9]+' --include='build.gradle*' . 2>/dev/null | head -1"
  },

  verify: {
    build: '  ./gradlew assembleDebug || fail "build"',
    test: [
      '  # `test` runs unit tests only. Instrumented tests are connectedAndroidTest',
      '  # and need a device or emulator — do not silently conflate the two.',
      '  ./gradlew test || fail "test"'
    ].join('\n'),
    lint: '  ./gradlew lint || fail "lint"'
  },

  pitfalls: [
    'Always run `./gradlew`, never a system `gradle`. The wrapper pins the version the project actually builds with; the system one silently builds something else.',
    '`./gradlew test` runs unit tests only. Instrumented tests (`connectedAndroidTest`) need a device and are a different task — a green `test` says nothing about them.',
    'The Gradle daemon and build cache can serve a green build for stale code. When a result looks impossible, `--no-daemon` or `clean` before believing it.',
    'A JDK mismatch between your machine and CI produces failures that reproduce nowhere. Pin the toolchain in the build script rather than relying on JAVA_HOME.'
  ],

  constitution: {
    architecture:
      '- UI observes state; it does not call repositories or network directly.\n- One module owns one feature; modules do not depend on each other sideways.',
    platform: '- JDK: {{javaVersion}} · Gradle wrapper: {{gradleVersion}} · {{compileSdk}}.\n- Pin the JDK in the build script; relying on JAVA_HOME produces failures that reproduce nowhere.',
    code:
      '- No `!!` in Kotlin without a comment proving non-null.\n- No secrets in `build.gradle` or committed properties files.\n- No blocking IO on the main thread.'
  },

  defaults: {
    baseBranch: 'main',
    branchPattern: 'feature/<topic>',
    featureIdExample: 'feat-042',
    techStack: 'Android, Gradle wrapper {{gradleVersion}}, {{javaVersion}}',
    structure: 'app/ plus feature modules, each with its own build.gradle.'
  }
};
