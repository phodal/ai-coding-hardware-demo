#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${VISUAL_SKETCH:-$ROOT_DIR/sketches/display_ocr_check}"
export BUILD_PATH="${VISUAL_BUILD_PATH:-$ROOT_DIR/.arduino-build/display_ocr_check}"
export OCR_EXPECTED="${OCR_EXPECTED:-CODEX OK}"

"$ROOT_DIR/scripts/upload.sh"

echo "Waiting for the display to settle before camera capture..."
sleep "${VISUAL_SETTLE_SECONDS:-4}"

"$ROOT_DIR/scripts/camera-ocr.sh"

