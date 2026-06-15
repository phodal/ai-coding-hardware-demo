#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${TINYML_IMU_SKETCH:-$ROOT_DIR/sketches/tinyml_imu_classifier}"
export BUILD_PATH="${TINYML_IMU_BUILD_PATH:-$ROOT_DIR/.arduino-build/tinyml_imu_classifier}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${TINYML_IMU_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

TINYML_CHECK_ARGS=(
  --port "$ARDUINO_PORT"
  --baud "${MONITOR_BAUD:-115200}"
  --seconds "${TINYML_IMU_SECONDS:-3}"
)

if [[ "${TINYML_IMU_ALLOW_IMU_MISSING:-0}" == "1" ]]; then
  TINYML_CHECK_ARGS+=(--allow-imu-missing)
fi

python3 "$ROOT_DIR/scripts/tinyml-imu-check.py" "${TINYML_CHECK_ARGS[@]}"

if [[ "${TINYML_IMU_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${TINYML_IMU_OCR_EXPECTED:-TINY}" \
    OCR_PREPROCESS_MODE="${OCR_PREPROCESS_MODE:-color}" \
    OCR_SCALE_WIDTH="${OCR_SCALE_WIDTH:-2400}" \
    "$ROOT_DIR/scripts/camera-ocr.sh"
fi
