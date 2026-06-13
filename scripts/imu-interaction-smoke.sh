#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${IMU_INTERACTION_SKETCH:-$ROOT_DIR/sketches/imu_interaction_probe}"
export BUILD_PATH="${IMU_INTERACTION_BUILD_PATH:-$ROOT_DIR/.arduino-build/imu_interaction_probe}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${IMU_INTERACTION_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

CHECK_ARGS=(
  --port "$ARDUINO_PORT"
  --baud "${MONITOR_BAUD:-115200}"
  --seconds "${IMU_INTERACTION_SECONDS:-2}"
)

if [[ "${IMU_INTERACTION_ALLOW_IMU_MISSING:-0}" == "1" ]]; then
  CHECK_ARGS+=(--allow-imu-missing)
fi

python3 "$ROOT_DIR/scripts/imu-interaction-check.py" "${CHECK_ARGS[@]}"

if [[ "${IMU_INTERACTION_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${IMU_INTERACTION_OCR_EXPECTED:-OK}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
