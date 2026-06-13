#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

SKETCH_DIR="${AUDIO_VAD_SKETCH:-$ROOT_DIR/sketches/audio_vad_probe}"
BUILD_DIR="${AUDIO_VAD_BUILD_PATH:-$ROOT_DIR/.arduino-build/audio_vad_probe}"
MAIN_INO="$SKETCH_DIR/audio_vad_probe.ino"
CHECKER="$ROOT_DIR/scripts/audio-vad-check.py"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "audio_vad_preflight missing_file path=$path" >&2
    exit 1
  fi
}

require_marker() {
  local marker="$1"
  local path="$2"
  if ! rg -F "$marker" "$path" >/dev/null; then
    echo "audio_vad_preflight missing_marker marker=$marker path=$path" >&2
    exit 1
  fi
}

require_artifact() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "audio_vad_preflight missing_artifact path=$path" >&2
    echo "Run make audio-vad-build before the quiet-window audio smoke." >&2
    exit 1
  fi
  printf 'audio_vad_preflight artifact=%s bytes=%s\n' "$path" "$(stat -f %z "$path")"
}

require_arduino_cli
require_vendor_libraries

if [[ -z "${ARDUINO_PORT:-}" ]]; then
  echo "audio_vad_preflight missing_port=set_ARDUINO_PORT_or_connect_board" >&2
  exit 1
fi

require_file "$MAIN_INO"
require_file "$SKETCH_DIR/es7210.cpp"
require_file "$SKETCH_DIR/es7210.h"
require_file "$SKETCH_DIR/audio_hal.h"
require_file "$SKETCH_DIR/pin_config.h"
require_file "$CHECKER"

require_marker "AUDIO_VAD_READY" "$MAIN_INO"
require_marker "AUDIO_METRIC" "$MAIN_INO"
require_marker "AUDIO_SPEECH_DETECTED" "$MAIN_INO"
require_marker "PIN_ES7210_BCLK" "$SKETCH_DIR/pin_config.h"
require_marker "PIN_ES7210_LRCK" "$SKETCH_DIR/pin_config.h"
require_marker "PIN_ES7210_DIN" "$SKETCH_DIR/pin_config.h"
require_marker "PIN_ES7210_MCLK" "$SKETCH_DIR/pin_config.h"

python3 "$CHECKER" --help | rg -- "--stimulus-command|--min-rms-delta|--require-speech" >/dev/null

require_artifact "$BUILD_DIR/audio_vad_probe.ino.bin"
require_artifact "$BUILD_DIR/audio_vad_probe.ino.bootloader.bin"
require_artifact "$BUILD_DIR/audio_vad_probe.ino.partitions.bin"
require_artifact "$BUILD_DIR/audio_vad_probe.ino.elf"

arduino-cli version
arduino-cli core list | rg "esp32:esp32[[:space:]]+${ARDUINO_CORE_VERSION}" >/dev/null

printf 'audio_vad_preflight status=ok port=%s sketch=%s build=%s audio_devices_used=0 stimulus_played=0 uploaded=0\n' \
  "$ARDUINO_PORT" "$SKETCH_DIR" "$BUILD_DIR"
