#!/bin/bash
# feat-012 (docs/02 §5, MOB budget): "Penambahan ukuran app ≤ 1,5 MB per platform (terkompresi)."
# Measures the REAL added footprint a consuming app pays for linking APMKit — building two
# throwaway executables (scripts/size-budget/) release-mode, with vs without APMKit linked,
# and diffing their gzip-compressed sizes. An "automatic" SPM library product (Package.swift)
# has no linked artifact of its own to measure directly; only a real consumer does, which is
# exactly what this pair of executables stands in for.
#
# "1.5 MB" interpreted as 1.5 * 1024 * 1024 bytes (binary MB) — the spec doesn't say which,
# this is a documented, defensible choice, not a silent assumption.
set -eo pipefail

cd "$(dirname "$0")/size-budget"

THRESHOLD_BYTES=$((1572864)) # 1.5 * 1024 * 1024

echo "Building size-budget probes (release)..."
swift build -c release 2>&1 | tail -20

BASELINE_BIN=".build/release/Baseline"
WITH_SDK_BIN=".build/release/WithSDK"

if [ ! -f "$BASELINE_BIN" ] || [ ! -f "$WITH_SDK_BIN" ]; then
  echo "BUDGET: FAIL (binary-size) — expected binaries not found after build"
  exit 1
fi

BASELINE_GZIP=$(gzip -c "$BASELINE_BIN" | wc -c | tr -d ' ')
WITH_SDK_GZIP=$(gzip -c "$WITH_SDK_BIN" | wc -c | tr -d ' ')
DELTA=$((WITH_SDK_GZIP - BASELINE_GZIP))

echo "Baseline (no APMKit), gzip:  ${BASELINE_GZIP} bytes"
echo "With APMKit linked, gzip:    ${WITH_SDK_GZIP} bytes"
echo "Delta (SDK's added size):   ${DELTA} bytes"
echo "Threshold (docs/02 §5):     ${THRESHOLD_BYTES} bytes (1.5 MB)"

if [ "$DELTA" -gt "$THRESHOLD_BYTES" ]; then
  echo "BUDGET: FAIL (binary-size) — ${DELTA} bytes exceeds the ${THRESHOLD_BYTES}-byte budget"
  exit 1
fi

echo "BUDGET: PASS (binary-size)"
