#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${DESK_WIDGET_SKETCH:-$ROOT_DIR/sketches/desk_widget}"
export BUILD_PATH="${DESK_WIDGET_BUILD_PATH:-$ROOT_DIR/.arduino-build/desk_widget}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${DESK_WIDGET_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

RELAY_ARGS=(
  --port "$ARDUINO_PORT"
  --baud "${MONITOR_BAUD:-115200}"
  --mode "${DESK_WIDGET_RELAY_MODE:-mock}"
  --timeout "${DESK_WIDGET_TIMEOUT:-15}"
)

if [[ -n "${DESK_WIDGET_EVENTS_JSON:-}" ]]; then
  RELAY_ARGS+=(--events-json "$DESK_WIDGET_EVENTS_JSON")
fi

if [[ -n "${DESK_WIDGET_RELAY_ENDPOINT:-}" ]]; then
  RELAY_ARGS+=(--endpoint "$DESK_WIDGET_RELAY_ENDPOINT")
fi

python3 "$ROOT_DIR/scripts/desk-widget-relay.py" "${RELAY_ARGS[@]}"

if [[ "${DESK_WIDGET_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${DESK_WIDGET_OCR_EXPECTED:-OK}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
