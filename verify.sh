#!/bin/bash
# Harness verification for APMKit. Run from repo root.
# Usage: ./verify.sh [build|test|lint|all]   (default: build)
# Always ends with a machine-parseable line: HARNESS_VERIFY: PASS|FAIL
set -eo pipefail

MODE="${1:-build}"

fail() { echo "HARNESS_VERIFY: FAIL ($1)"; exit 1; }

run_build() {
  set +e
  swift build 2>&1 | tee /tmp/verify_build.log | tail -40
  local status="${PIPESTATUS[0]}"
  set -e
  [ "$status" -eq 0 ] || fail "build"
}

run_test() {
  set +e
  swift test 2>&1 | tee /tmp/verify_test.log | tail -60
  local status="${PIPESTATUS[0]}"
  set -e
  [ "$status" -eq 0 ] || fail "test"
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
