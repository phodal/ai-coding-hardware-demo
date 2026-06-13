#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required for image processing." >&2
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
CAMERA_RAW_IMAGE="${CAMERA_RAW_IMAGE:-}"
CAMERA_WARMUP_FRAMES="${CAMERA_WARMUP_FRAMES:-3}"
CAMERA_EXPOSURE_BIAS="${CAMERA_EXPOSURE_BIAS:-}"
CAMERA_EXPOSURE_POINT="${CAMERA_EXPOSURE_POINT:-}"
CAMERA_FOCUS_POINT="${CAMERA_FOCUS_POINT:-}"
OCR_ROTATE="${OCR_ROTATE:-0}"
OCR_EXPECTED="${OCR_EXPECTED:-OK}"
OCR_LANG="${OCR_LANG:-eng}"
OCR_ENGINE="${OCR_ENGINE:-vision}"
CAMERA_CAPTURE_TIMEOUT="${CAMERA_CAPTURE_TIMEOUT:-15}"
CAMERA_CAPTURE_ENGINE="${CAMERA_CAPTURE_ENGINE:-auto}"
CAMERA_SNAPSHOT_FORMAT="${CAMERA_SNAPSHOT_FORMAT:-jpeg}"
OCR_PREPROCESS_MODE="${OCR_PREPROCESS_MODE:-gray}"

case "$OCR_PREPROCESS_MODE" in
  amoled)
    OCR_EQ_CONTRAST="${OCR_EQ_CONTRAST:-2.0}"
    OCR_EQ_BRIGHTNESS="${OCR_EQ_BRIGHTNESS:--0.30}"
    OCR_GAMMA="${OCR_GAMMA:-0.75}"
    ;;
  *)
    OCR_EQ_CONTRAST="${OCR_EQ_CONTRAST:-1.6}"
    OCR_EQ_BRIGHTNESS="${OCR_EQ_BRIGHTNESS:-0.02}"
    OCR_GAMMA="${OCR_GAMMA:-1.0}"
    ;;
esac

OCR_SCALE_WIDTH="${OCR_SCALE_WIDTH:-1920}"
OCR_UNSHARP="${OCR_UNSHARP:-5:5:1.0}"
OCR_INVERT="${OCR_INVERT:-0}"
OCR_FILTER_EXTRA="${OCR_FILTER_EXTRA:-}"

mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
RAW_IMAGE="$LOG_DIR/camera-ocr-$STAMP.jpg"
PROCESSED_IMAGE="$LOG_DIR/camera-ocr-$STAMP.processed.png"
OCR_TEXT_FILE="$LOG_DIR/camera-ocr-$STAMP.txt"

if [[ -n "$CAMERA_RAW_IMAGE" ]]; then
  RAW_IMAGE="$CAMERA_RAW_IMAGE"
fi

capture_with_swift() {
  if ! command -v swift >/dev/null 2>&1; then
    return 127
  fi
  echo "Capturing camera device $CAMERA_DEVICE via CameraSnapshot at $CAMERA_SIZE -> $RAW_IMAGE"
  local args=(
    swift run --package-path "$ROOT_DIR" CameraSnapshot
    --device "$CAMERA_DEVICE" \
    --output "$RAW_IMAGE" \
    --timeout "$CAMERA_CAPTURE_TIMEOUT" \
    --size "$CAMERA_SIZE" \
    --format "$CAMERA_SNAPSHOT_FORMAT" \
    --warmup-frames "$CAMERA_WARMUP_FRAMES"
  )
  if [[ -n "$CAMERA_EXPOSURE_BIAS" ]]; then
    args+=(--exposure-bias "$CAMERA_EXPOSURE_BIAS")
  fi
  if [[ -n "$CAMERA_EXPOSURE_POINT" ]]; then
    args+=(--exposure-point "$CAMERA_EXPOSURE_POINT")
  fi
  if [[ -n "$CAMERA_FOCUS_POINT" ]]; then
    args+=(--focus-point "$CAMERA_FOCUS_POINT")
  fi
  "${args[@]}"
}

capture_with_ffmpeg() {
  echo "Capturing camera device $CAMERA_DEVICE via ffmpeg at $CAMERA_SIZE ($CAMERA_PIXEL_FORMAT) -> $RAW_IMAGE"
  perl -e 'alarm shift; exec @ARGV' "$CAMERA_CAPTURE_TIMEOUT" ffmpeg \
    -hide_banner \
    -loglevel error \
    -f avfoundation \
    -framerate 30 \
    -pixel_format "$CAMERA_PIXEL_FORMAT" \
    -video_size "$CAMERA_SIZE" \
    -i "$CAMERA_DEVICE:none" \
    -frames:v 1 \
    -y "$RAW_IMAGE"
}

if [[ -n "$CAMERA_RAW_IMAGE" ]]; then
  echo "Using existing camera image -> $RAW_IMAGE"
else
  case "$CAMERA_CAPTURE_ENGINE" in
    auto)
      if ! capture_with_swift; then
        echo "Swift camera capture failed; falling back to ffmpeg." >&2
        if ! capture_with_ffmpeg; then
          echo "Camera capture failed or timed out after ${CAMERA_CAPTURE_TIMEOUT}s." >&2
          exit 124
        fi
      fi
      ;;
    swift)
      if ! capture_with_swift; then
        echo "Swift camera capture failed or timed out after ${CAMERA_CAPTURE_TIMEOUT}s." >&2
        exit 124
      fi
      ;;
    ffmpeg)
      if ! capture_with_ffmpeg; then
        echo "ffmpeg camera capture failed or timed out after ${CAMERA_CAPTURE_TIMEOUT}s." >&2
        exit 124
      fi
      ;;
    *)
      echo "CAMERA_CAPTURE_ENGINE must be one of: auto, swift, ffmpeg" >&2
      exit 2
      ;;
  esac
fi

if [[ ! -s "$RAW_IMAGE" ]]; then
  echo "Camera capture did not produce an image: $RAW_IMAGE" >&2
  exit 1
fi

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

build_ocr_filter() {
  local filter="crop=$CAMERA_CROP${ROTATE_FILTER}"

  if [[ "$OCR_SCALE_WIDTH" != "0" ]]; then
    filter+=",scale=$OCR_SCALE_WIDTH:-1"
  fi

  case "$OCR_PREPROCESS_MODE" in
    none)
      ;;
    color)
      filter+=",eq=contrast=$OCR_EQ_CONTRAST:brightness=$OCR_EQ_BRIGHTNESS:gamma=$OCR_GAMMA"
      ;;
    gray)
      filter+=",format=gray,eq=contrast=$OCR_EQ_CONTRAST:brightness=$OCR_EQ_BRIGHTNESS:gamma=$OCR_GAMMA"
      ;;
    amoled)
      filter+=",eq=contrast=$OCR_EQ_CONTRAST:brightness=$OCR_EQ_BRIGHTNESS:gamma=$OCR_GAMMA"
      ;;
    *)
      echo "OCR_PREPROCESS_MODE must be one of: none, color, gray, amoled" >&2
      exit 2
      ;;
  esac

  if [[ "$OCR_INVERT" == "1" ]]; then
    filter+=",negate"
  elif [[ "$OCR_INVERT" != "0" ]]; then
    echo "OCR_INVERT must be 0 or 1" >&2
    exit 2
  fi

  if [[ -n "$OCR_UNSHARP" && "$OCR_UNSHARP" != "0" ]]; then
    filter+=",unsharp=$OCR_UNSHARP"
  fi

  if [[ -n "$OCR_FILTER_EXTRA" ]]; then
    filter+=",$OCR_FILTER_EXTRA"
  fi

  printf '%s' "$filter"
}

OCR_FILTER="$(build_ocr_filter)"

ffmpeg \
  -hide_banner \
  -loglevel error \
  -i "$RAW_IMAGE" \
  -vf "$OCR_FILTER" \
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
echo "  capture:   $CAMERA_CAPTURE_ENGINE"
echo "  mode:      $OCR_PREPROCESS_MODE"
echo "  filter:    $OCR_FILTER"
if [[ -n "$CAMERA_EXPOSURE_BIAS" ]]; then
  echo "  exposure:  $CAMERA_EXPOSURE_BIAS"
fi

if [[ "$NORMALIZED_TEXT" == *"$NORMALIZED_EXPECTED"* ]]; then
  echo "OCR validation passed."
  exit 0
fi

echo "OCR validation failed: normalized text '$NORMALIZED_TEXT' did not contain '$NORMALIZED_EXPECTED'." >&2
exit 1
