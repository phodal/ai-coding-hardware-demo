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
MIN_X_GAP="${COLOR_SWATCH_MIN_X_GAP:-20}"
MAX_Y_SPREAD="${COLOR_SWATCH_MAX_Y_SPREAD:-45}"
GEOMETRY_ARGS=(--min-x-gap "$MIN_X_GAP" --max-y-spread "$MAX_Y_SPREAD")
if [[ "${COLOR_SWATCH_GEOMETRY:-1}" == "0" ]]; then
  GEOMETRY_ARGS=(--skip-geometry)
fi

swift run --package-path "$ROOT_DIR" ColorSwatchCheck \
  --image "$IMAGE" \
  --roi "$ROI" \
  --min-pixels "$MIN_PIXELS" \
  --step "$STEP" \
  "${GEOMETRY_ARGS[@]}"
