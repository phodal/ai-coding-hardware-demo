#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${WIFI_CONNECTIVITY_SKETCH:-$ROOT_DIR/sketches/wifi_connectivity_probe}"
export BUILD_PATH="${WIFI_CONNECTIVITY_BUILD_PATH:-$ROOT_DIR/.arduino-build/wifi_connectivity_probe}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${WIFI_CONNECTIVITY_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

CHECK_ARGS=(
  --port "$ARDUINO_PORT"
  --baud "${MONITOR_BAUD:-115200}"
  --seconds "${WIFI_CONNECTIVITY_SECONDS:-2}"
  --min-networks "${WIFI_MIN_NETWORKS:-0}"
)

if [[ -n "${WIFI_TEST_SSID:-}" || -n "${WIFI_TEST_PASSWORD:-}" ]]; then
  if [[ -z "${WIFI_TEST_SSID:-}" || -z "${WIFI_TEST_PASSWORD:-}" ]]; then
    echo "WIFI_TEST_SSID and WIFI_TEST_PASSWORD must be set together." >&2
    exit 2
  fi
  CHECK_ARGS+=(--ssid "$WIFI_TEST_SSID" --password "$WIFI_TEST_PASSWORD")
fi

python3 "$ROOT_DIR/scripts/wifi-connectivity-check.py" "${CHECK_ARGS[@]}"

if [[ "${WIFI_CONNECTIVITY_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${WIFI_CONNECTIVITY_OCR_EXPECTED:-OK}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
