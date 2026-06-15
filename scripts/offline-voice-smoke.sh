#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${OFFLINE_VOICE_SKETCH:-$ROOT_DIR/sketches/offline_voice_control}"
export BUILD_PATH="${OFFLINE_VOICE_BUILD_PATH:-$ROOT_DIR/.arduino-build/offline_voice_control}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${OFFLINE_VOICE_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

OFFLINE_VOICE_CHECK_ARGS=(
  --port "$ARDUINO_PORT"
  --baud "${MONITOR_BAUD:-115200}"
  --seconds "${OFFLINE_VOICE_SECONDS:-4}"
)

if [[ "${OFFLINE_VOICE_ALLOW_TOUCH_MISSING:-0}" == "1" ]]; then
  OFFLINE_VOICE_CHECK_ARGS+=(--allow-touch-missing)
fi

python3 "$ROOT_DIR/scripts/offline-voice-check.py" "${OFFLINE_VOICE_CHECK_ARGS[@]}"

if [[ "${OFFLINE_VOICE_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${OFFLINE_VOICE_OCR_EXPECTED:-VOICE}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
