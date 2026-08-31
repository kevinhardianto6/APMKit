#!/bin/bash
# Harness verification for APMKit. Run from repo root.
# Usage: ./verify.sh [build|test|lint|budget|podspec|all]   (default: build)
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

# feat-013 (MOB-23): validates APMKit.podspec actually resolves and links under CocoaPods —
# not just that the manifest parses. Fetches KSCrash over the network and builds a throwaway
# host app, so it's slower than the rest of `verify.sh` (~1-2 min) and network-dependent;
# that's why it's its own mode rather than folded silently into `test`. Requires the `pod`
# CLI (CocoaPods) — GitHub-hosted macOS runners have it preinstalled.
run_podspec() {
  if ! command -v pod >/dev/null 2>&1; then
    fail "podspec (CocoaPods 'pod' CLI not found — install with 'gem install cocoapods')"
  fi
  set +e
  pod lib lint APMKit.podspec --allow-warnings --sources=https://cdn.cocoapods.org/ 2>&1 | tee /tmp/verify_podspec.log | tail -30
  local status="${PIPESTATUS[0]}"
  set -e
  [ "$status" -eq 0 ] || fail "podspec"
}

case "$MODE" in
  build)    run_build ;;
  test)     run_test ;;
  lint)     run_lint ;;
  budget)   run_budget ;;
  podspec)  run_podspec ;;
  all)      run_build && run_test && run_lint && run_budget && run_podspec ;;
  *)        echo "Unknown mode: $MODE (use build|test|lint|budget|podspec|all)"; exit 2 ;;
esac

echo "HARNESS_VERIFY: PASS ($MODE)"
