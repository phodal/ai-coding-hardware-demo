#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

export SKETCH="${AUDIO_VAD_SKETCH:-$ROOT_DIR/sketches/audio_vad_probe}"
export BUILD_PATH="${AUDIO_VAD_BUILD_PATH:-$ROOT_DIR/.arduino-build/audio_vad_probe}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

"$ROOT_DIR/scripts/upload.sh"
sleep "${AUDIO_VAD_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

python3 "$ROOT_DIR/scripts/audio-vad-check.py" \
  --port "$ARDUINO_PORT" \
  --baud "${MONITOR_BAUD:-115200}" \
  --baseline-seconds "${AUDIO_VAD_BASELINE_SECONDS:-2}" \
  --active-seconds "${AUDIO_VAD_ACTIVE_SECONDS:-8}" \
  --stimulus-command "${AUDIO_VAD_STIMULUS_COMMAND:-say 'hello xiao zhi audio probe, testing microphone input'}" \
  --min-rms "${AUDIO_VAD_MIN_RMS:-5}" \
  --min-peak "${AUDIO_VAD_MIN_PEAK:-20}" \
  --min-rms-delta "${AUDIO_VAD_MIN_RMS_DELTA:-5}" \
  --min-peak-delta "${AUDIO_VAD_MIN_PEAK_DELTA:-10}" \
  ${AUDIO_VAD_REQUIRE_SPEECH:+--require-speech}

if [[ "${AUDIO_VAD_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${AUDIO_VAD_OCR_EXPECTED:-OK}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
