#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${LVGL_VISUAL_AGENT_SKETCH:-$ROOT_DIR/sketches/lvgl_visual_agent}"
export BUILD_PATH="${LVGL_VISUAL_AGENT_BUILD_PATH:-$ROOT_DIR/.arduino-build/lvgl_visual_agent}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${LVGL_VISUAL_AGENT_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

LVGL_VISUAL_AGENT_CHECK_ARGS=(
  --port "$ARDUINO_PORT"
  --baud "${MONITOR_BAUD:-115200}"
  --seconds "${LVGL_VISUAL_AGENT_SECONDS:-4}"
)

if [[ "${LVGL_VISUAL_AGENT_ALLOW_TOUCH_MISSING:-0}" == "1" ]]; then
  LVGL_VISUAL_AGENT_CHECK_ARGS+=(--allow-touch-missing)
fi

python3 "$ROOT_DIR/scripts/lvgl-visual-agent-check.py" "${LVGL_VISUAL_AGENT_CHECK_ARGS[@]}"

if [[ "${LVGL_VISUAL_AGENT_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${LVGL_VISUAL_AGENT_OCR_EXPECTED:-OK}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
