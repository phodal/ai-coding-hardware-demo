#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

require_arduino_cli
require_vendor_libraries

mkdir -p "$BUILD_PATH"

arduino-cli compile \
  --clean \
  --jobs 1 \
  --fqbn "$ARDUINO_FQBN" \
  --libraries "$WAVESHARE_LIBRARIES" \
  --build-path "$BUILD_PATH" \
  "$SKETCH"

