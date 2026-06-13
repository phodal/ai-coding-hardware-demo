#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${SPEAKER_OUTPUT_SKETCH:-$ROOT_DIR/sketches/speaker_output_probe}"
export BUILD_PATH="${SPEAKER_OUTPUT_BUILD_PATH:-$ROOT_DIR/.arduino-build/speaker_output_probe}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${SPEAKER_OUTPUT_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
SPEAKER_WAV="${SPEAKER_OUTPUT_WAV:-$LOG_DIR/speaker-output-$STAMP.wav}"

python3 "$ROOT_DIR/scripts/speaker-output-check.py" \
  --port "$ARDUINO_PORT" \
  --baud "${MONITOR_BAUD:-115200}" \
  --audio-device "${SPEAKER_AUDIO_DEVICE:-1}" \
  --sample-rate "${SPEAKER_AUDIO_SAMPLE_RATE:-16000}" \
  --baseline-seconds "${SPEAKER_BASELINE_SECONDS:-2}" \
  --active-seconds "${SPEAKER_ACTIVE_SECONDS:-5}" \
  --settle-seconds "${SPEAKER_SETTLE_SECONDS:-0.5}" \
  --out "$SPEAKER_WAV" \
  --min-active-rms "${SPEAKER_MIN_ACTIVE_RMS:-500}" \
  --min-rms-delta "${SPEAKER_MIN_RMS_DELTA:-200}" \
  --min-ratio "${SPEAKER_MIN_RATIO:-1.8}"

if [[ "${SPEAKER_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${SPEAKER_OCR_EXPECTED:-OK}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
