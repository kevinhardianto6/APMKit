#!/bin/bash
# Harness verification for APMKit. Run from repo root.
# Usage: ./verify.sh [build|test|lint|budget|all]   (default: build)
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

# feat-012 (docs/02 §5): binary-size budget only — CPU/memory/cold-start need real-device
# profiling under realistic load, not something a CI runner can measure honestly (see
# FEATURES.md's feat-012 entry and the pilot's manual verification checklist). Main-thread
# I/O is checked structurally as part of `run_test` (Tests/APMKitTests/Sync/
# MainThreadIOStructuralTests.swift), not a separate step here.
run_budget() {
  set +e
  ./scripts/check-binary-size-budget.sh 2>&1 | tee /tmp/verify_budget.log | tail -20
  local status="${PIPESTATUS[0]}"
  set -e
  [ "$status" -eq 0 ] || fail "budget"
}

case "$MODE" in
  build)  run_build ;;
  test)   run_test ;;
  lint)   run_lint ;;
  budget) run_budget ;;
  all)    run_build && run_test && run_lint && run_budget ;;
  *)      echo "Unknown mode: $MODE (use build|test|lint|budget|all)"; exit 2 ;;
esac

echo "HARNESS_VERIFY: PASS ($MODE)"
