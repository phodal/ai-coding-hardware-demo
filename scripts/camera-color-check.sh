#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

IMAGE="${1:-${COLOR_SWATCH_IMAGE:-}}"
if [[ -z "$IMAGE" ]]; then
  echo "Usage: camera-color-check.sh <image-path>" >&2
  exit 2
fi

if [[ ! -s "$IMAGE" ]]; then
  echo "Color swatch image is missing or empty: $IMAGE" >&2
  exit 1
fi

ROI="${COLOR_SWATCH_ROI:-0.35,0.35,0.40,0.40}"
MIN_PIXELS="${COLOR_SWATCH_MIN_PIXELS:-25}"
STEP="${COLOR_SWATCH_STEP:-2}"

swift run --package-path "$ROOT_DIR" ColorSwatchCheck \
  --image "$IMAGE" \
  --roi "$ROI" \
  --min-pixels "$MIN_PIXELS" \
  --step "$STEP"
