#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${TOUCH_STATUS_SKETCH:-$ROOT_DIR/sketches/touch_status_probe}"
export BUILD_PATH="${TOUCH_STATUS_BUILD_PATH:-$ROOT_DIR/.arduino-build/touch_status_probe}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${TOUCH_STATUS_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

TOUCH_CHECK_ARGS=(
  --port "$ARDUINO_PORT" \
  --baud "${MONITOR_BAUD:-115200}" \
  --seconds "${TOUCH_STATUS_SECONDS:-8}" \
  --min-points "${TOUCH_MIN_POINTS:-1}"
)

if [[ "${TOUCH_REQUIRE_EVENT:-0}" == "1" ]]; then
  TOUCH_CHECK_ARGS+=(--require-event)
fi

python3 "$ROOT_DIR/scripts/touch-status-check.py" "${TOUCH_CHECK_ARGS[@]}"

if [[ "${TOUCH_STATUS_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${TOUCH_STATUS_OCR_EXPECTED:-OK}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
