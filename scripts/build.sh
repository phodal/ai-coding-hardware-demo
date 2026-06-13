#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

require_arduino_cli
require_vendor_libraries

mkdir -p "$BUILD_PATH"

COMPILE_ARGS=(
  compile
  --clean
  --jobs 1
  --fqbn "$ARDUINO_FQBN"
  --libraries "$WAVESHARE_LIBRARIES"
  --build-path "$BUILD_PATH"
)

if [[ -n "${ARDUINO_BUILD_PROPERTY:-}" ]]; then
  COMPILE_ARGS+=(--build-property "$ARDUINO_BUILD_PROPERTY")
fi

arduino-cli "${COMPILE_ARGS[@]}" "$SKETCH"
