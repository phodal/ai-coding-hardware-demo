#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

CAMERA_DEVICE="${CAMERA_DEVICE:-0}"
CAMERA_SIZE="${CAMERA_SIZE:-1280x720}"
CAMERA_PIXEL_FORMAT="${CAMERA_PIXEL_FORMAT:-uyvy422}"
CAMERA_CAPTURE_TIMEOUT="${CAMERA_CAPTURE_TIMEOUT:-6}"
CAMERA_DIAGNOSE_CAPTURE="${CAMERA_DIAGNOSE_CAPTURE:-1}"
CAMERA_DIAGNOSE_FFMPEG="${CAMERA_DIAGNOSE_FFMPEG:-1}"
CAMERA_DIAGNOSE_REQUIRE_CAPTURE="${CAMERA_DIAGNOSE_REQUIRE_CAPTURE:-0}"

mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
DIAG_DIR="$LOG_DIR/camera-diagnose-$STAMP"
mkdir -p "$DIAG_DIR"

run_section() {
  local name="$1"
  shift
  echo "== $name =="
  "$@" 2>&1 | tee "$DIAG_DIR/$name.log"
}

run_optional_section() {
  local name="$1"
  shift
  echo "== $name =="
  set +e
  "$@" 2>&1 | tee "$DIAG_DIR/$name.log"
  local status=${PIPESTATUS[0]}
  set -e
  echo "$status" >"$DIAG_DIR/$name.status"
  return "$status"
}

run_section system-profiler system_profiler SPCameraDataType
run_section camera-snapshot-list swift run --package-path "$ROOT_DIR" CameraSnapshot --list
run_section camera-processes bash -c \
  "ps -axo pid,ppid,stat,etime,command | rg 'FaceTime|WeChat|WeCom|Camera|Continuity|Photo Booth|zoom|Teams|腾讯会议|ffmpeg|CameraAligner|CameraSnapshot' || true"

SWIFT_STATUS=0
FFMPEG_STATUS=0

if [[ "$CAMERA_DIAGNOSE_CAPTURE" == "1" ]]; then
  SWIFT_IMAGE="$DIAG_DIR/swift-capture.jpg"
  run_optional_section swift-capture swift run --package-path "$ROOT_DIR" CameraSnapshot \
    --device "$CAMERA_DEVICE" \
    --output "$SWIFT_IMAGE" \
    --timeout "$CAMERA_CAPTURE_TIMEOUT" \
    --size "$CAMERA_SIZE" \
    --format jpeg || SWIFT_STATUS=$?
fi

if [[ "$CAMERA_DIAGNOSE_FFMPEG" == "1" ]]; then
  FFMPEG_IMAGE="$DIAG_DIR/ffmpeg-capture.jpg"
  run_optional_section ffmpeg-capture perl -e 'alarm shift; exec @ARGV' "$CAMERA_CAPTURE_TIMEOUT" ffmpeg \
    -hide_banner \
    -loglevel error \
    -f avfoundation \
    -framerate 30 \
    -pixel_format "$CAMERA_PIXEL_FORMAT" \
    -video_size "$CAMERA_SIZE" \
    -i "$CAMERA_DEVICE:none" \
    -frames:v 1 \
    -y "$FFMPEG_IMAGE" || FFMPEG_STATUS=$?
fi

{
  echo "camera_diagnose_dir=$DIAG_DIR"
  echo "camera_device=$CAMERA_DEVICE"
  echo "camera_size=$CAMERA_SIZE"
  echo "swift_capture_status=$SWIFT_STATUS"
  echo "ffmpeg_capture_status=$FFMPEG_STATUS"
} | tee "$DIAG_DIR/summary.txt"

if [[ "$CAMERA_DIAGNOSE_REQUIRE_CAPTURE" == "1" && "$SWIFT_STATUS" != "0" && "$FFMPEG_STATUS" != "0" ]]; then
  echo "Camera diagnose did not capture a frame with either engine." >&2
  exit 1
fi
