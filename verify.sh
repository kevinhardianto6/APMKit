#!/bin/bash
# Harness verification for APMKit. Run from repo root.
# Usage: ./verify.sh [build|test|lint|all]   (default: build)
# Always ends with a machine-parseable line: HARNESS_VERIFY: PASS|FAIL
set -eo pipefail

MODE="${1:-build}"

fail() { echo "HARNESS_VERIFY: FAIL ($1)"; exit 1; }

run_build() {
  xcodebuild -project "APMKit.xcodeproj" -scheme "APMKit" \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" build \
    | tee /tmp/verify_build.log | tail -20
  grep -q "BUILD SUCCEEDED" /tmp/verify_build.log || fail "build"
}

run_test() {
  xcodebuild -project "APMKit.xcodeproj" -scheme "APMKit" \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" test \
    | tee /tmp/verify_test.log | tail -40
  grep -q "TEST SUCCEEDED" /tmp/verify_test.log || fail "test"
}

run_lint() {
  echo "No lint check configured for this project."
}

case "$MODE" in
  build) run_build ;;
  test)  run_test ;;
  lint)  run_lint ;;
  all)   run_build && run_test && run_lint ;;
  *)     echo "Unknown mode: $MODE (use build|test|lint|all)"; exit 2 ;;
esac

echo "HARNESS_VERIFY: PASS ($MODE)"
