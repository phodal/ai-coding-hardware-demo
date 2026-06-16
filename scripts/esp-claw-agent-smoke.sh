#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${ESP_CLAW_AGENT_SKETCH:-$ROOT_DIR/sketches/esp_claw_agent}"
export BUILD_PATH="${ESP_CLAW_AGENT_BUILD_PATH:-$ROOT_DIR/.arduino-build/esp_claw_agent}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export DISPLAY_BRIGHTNESS="${DISPLAY_BRIGHTNESS:-96}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION -DDISPLAY_BRIGHTNESS=$DISPLAY_BRIGHTNESS}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${ESP_CLAW_AGENT_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

ESP_CLAW_AGENT_CHECK_ARGS=(
  --port "$ARDUINO_PORT"
  --baud "${MONITOR_BAUD:-115200}"
  --seconds "${ESP_CLAW_AGENT_SECONDS:-4}"
)

if [[ "${ESP_CLAW_AGENT_ALLOW_TOUCH_MISSING:-0}" == "1" ]]; then
  ESP_CLAW_AGENT_CHECK_ARGS+=(--allow-touch-missing)
fi

python3 "$ROOT_DIR/scripts/esp-claw-agent-check.py" "${ESP_CLAW_AGENT_CHECK_ARGS[@]}"

if [[ "${ESP_CLAW_AGENT_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${ESP_CLAW_AGENT_OCR_EXPECTED:-OK}" \
    OCR_PREPROCESS_MODE="${OCR_PREPROCESS_MODE:-color}" \
    OCR_SCALE_WIDTH="${OCR_SCALE_WIDTH:-2400}" \
    "$ROOT_DIR/scripts/camera-ocr.sh"
fi
