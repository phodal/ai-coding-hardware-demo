#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${CLOUD_AI_SKETCH:-$ROOT_DIR/sketches/cloud_ai_terminal}"
export BUILD_PATH="${CLOUD_AI_BUILD_PATH:-$ROOT_DIR/.arduino-build/cloud_ai_terminal}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${CLOUD_AI_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

python3 "$ROOT_DIR/scripts/cloud-ai-relay.py" \
  --port "$ARDUINO_PORT" \
  --baud "${MONITOR_BAUD:-115200}" \
  --mode "${CLOUD_AI_RELAY_MODE:-mock}" \
  ${CLOUD_AI_RELAY_ENDPOINT:+--endpoint "$CLOUD_AI_RELAY_ENDPOINT"} \
  --question "${CLOUD_AI_QUESTION:-hello from codex}" \
  --response "${CLOUD_AI_RESPONSE:-AI OK}" \
  --expect "${CLOUD_AI_EXPECT_SERIAL:-AI_DISPLAYED}" \
  --timeout "${CLOUD_AI_TIMEOUT:-15}"

if [[ "${CLOUD_AI_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${CLOUD_AI_OCR_EXPECTED:-OK}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
