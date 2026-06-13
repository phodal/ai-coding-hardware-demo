#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${POWER_LIFECYCLE_SKETCH:-$ROOT_DIR/sketches/power_lifecycle_probe}"
export BUILD_PATH="${POWER_LIFECYCLE_BUILD_PATH:-$ROOT_DIR/.arduino-build/power_lifecycle_probe}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${POWER_LIFECYCLE_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

CHECK_ARGS=(
  --port "$ARDUINO_PORT"
  --baud "${MONITOR_BAUD:-115200}"
  --seconds "${POWER_LIFECYCLE_SECONDS:-5}"
  --min-system-mv "${POWER_MIN_SYSTEM_MV:-2500}"
  --min-batt-mv "${POWER_MIN_BATT_MV:-3000}"
)

if [[ "${POWER_REQUIRE_BATTERY:-0}" == "1" ]]; then
  CHECK_ARGS+=(--require-battery)
fi

python3 "$ROOT_DIR/scripts/power-lifecycle-check.py" "${CHECK_ARGS[@]}"

if [[ "${POWER_LIFECYCLE_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${POWER_LIFECYCLE_OCR_EXPECTED:-OK}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
