#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

require_arduino_cli
require_vendor_libraries

if [[ -z "${ARDUINO_PORT:-}" ]]; then
  echo "No upload port detected. Set ARDUINO_PORT or reconnect the board." >&2
  arduino-cli board list
  exit 1
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$ROOT_DIR/scripts/build.sh"
fi

UPLOAD_ARGS=(
  --fqbn "$ARDUINO_FQBN"
  --port "$ARDUINO_PORT"
  --build-path "$BUILD_PATH"
)

if [[ "${VERIFY_UPLOAD:-0}" == "1" ]]; then
  UPLOAD_ARGS+=(--verify)
fi

arduino-cli upload "${UPLOAD_ARGS[@]}" "$SKETCH"

