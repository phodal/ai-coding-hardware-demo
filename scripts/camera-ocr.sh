#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required for camera capture." >&2
  exit 1
fi

if ! command -v tesseract >/dev/null 2>&1; then
  TESSERACT_AVAILABLE=0
else
  TESSERACT_AVAILABLE=1
fi

CAMERA_DEVICE="${CAMERA_DEVICE:-0}"
CAMERA_SIZE="${CAMERA_SIZE:-1280x720}"
CAMERA_PIXEL_FORMAT="${CAMERA_PIXEL_FORMAT:-uyvy422}"
CAMERA_CROP="${CAMERA_CROP:-iw*0.55:ih*0.65:(iw-ow)/2:(ih-oh)/2}"
OCR_ROTATE="${OCR_ROTATE:-0}"
OCR_EXPECTED="${OCR_EXPECTED:-OK}"
OCR_LANG="${OCR_LANG:-eng}"
OCR_ENGINE="${OCR_ENGINE:-vision}"

mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
RAW_IMAGE="$LOG_DIR/camera-ocr-$STAMP.jpg"
PROCESSED_IMAGE="$LOG_DIR/camera-ocr-$STAMP.processed.png"
OCR_TEXT_FILE="$LOG_DIR/camera-ocr-$STAMP.txt"

echo "Capturing camera device $CAMERA_DEVICE at $CAMERA_SIZE ($CAMERA_PIXEL_FORMAT) -> $RAW_IMAGE"

ffmpeg \
  -hide_banner \
  -loglevel error \
  -f avfoundation \
  -framerate 30 \
  -pixel_format "$CAMERA_PIXEL_FORMAT" \
  -video_size "$CAMERA_SIZE" \
  -i "$CAMERA_DEVICE:none" \
  -frames:v 1 \
  -y "$RAW_IMAGE"

case "$OCR_ROTATE" in
  0)
    ROTATE_FILTER=""
    ;;
  90)
    ROTATE_FILTER=",transpose=1"
    ;;
  180)
    ROTATE_FILTER=",hflip,vflip"
    ;;
  270)
    ROTATE_FILTER=",transpose=2"
    ;;
  *)
    echo "OCR_ROTATE must be one of: 0, 90, 180, 270" >&2
    exit 2
    ;;
esac

ffmpeg \
  -hide_banner \
  -loglevel error \
  -i "$RAW_IMAGE" \
  -vf "crop=$CAMERA_CROP${ROTATE_FILTER},scale=1920:-1,format=gray,eq=contrast=1.6:brightness=0.02,unsharp=5:5:1.0" \
  -y "$PROCESSED_IMAGE"

if [[ "$OCR_ENGINE" == "vision" ]]; then
  if ! command -v swift >/dev/null 2>&1; then
    echo "swift is required for OCR_ENGINE=vision." >&2
    exit 1
  fi
  {
    swift "$ROOT_DIR/scripts/vision-ocr.swift" "$PROCESSED_IMAGE"
    swift "$ROOT_DIR/scripts/vision-ocr.swift" "$RAW_IMAGE"
  } >"$OCR_TEXT_FILE" 2>"$LOG_DIR/camera-ocr-$STAMP.vision.log"
else
  if [[ "$TESSERACT_AVAILABLE" != "1" ]]; then
    echo "tesseract is required for OCR_ENGINE=tesseract." >&2
    exit 1
  fi
  tesseract "$PROCESSED_IMAGE" stdout --psm "${OCR_PSM:-6}" -l "$OCR_LANG" >"$OCR_TEXT_FILE" 2>"$LOG_DIR/camera-ocr-$STAMP.tesseract.log"
fi

OCR_TEXT="$(tr -d '\r' < "$OCR_TEXT_FILE")"
NORMALIZED_TEXT="$(printf '%s' "$OCR_TEXT" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9')"
NORMALIZED_EXPECTED="$(printf '%s' "$OCR_EXPECTED" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9')"

echo "OCR expected: $OCR_EXPECTED"
echo "OCR text:"
printf '%s\n' "$OCR_TEXT"
echo "Artifacts:"
echo "  raw:       $RAW_IMAGE"
echo "  processed: $PROCESSED_IMAGE"
echo "  text:      $OCR_TEXT_FILE"
echo "  crop:      $CAMERA_CROP"
echo "  rotate:    $OCR_ROTATE"
echo "  engine:    $OCR_ENGINE"

if [[ "$NORMALIZED_TEXT" == *"$NORMALIZED_EXPECTED"* ]]; then
  echo "OCR validation passed."
  exit 0
fi

echo "OCR validation failed: normalized text '$NORMALIZED_TEXT' did not contain '$NORMALIZED_EXPECTED'." >&2
exit 1
