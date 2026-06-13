#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-help}"
PROJECT_DIR="${2:-$PWD}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
EXTRA_ARGS=("${@:3}")

case "$ACTION" in
  setup|build|upload|monitor|smoke)
    if [[ -x "$PROJECT_DIR/scripts/$ACTION.sh" ]]; then
      exec "$PROJECT_DIR/scripts/$ACTION.sh"
    fi
    ;;
  visual-smoke)
    if [[ -x "$PROJECT_DIR/scripts/visual-smoke.sh" ]]; then
      exec "$PROJECT_DIR/scripts/visual-smoke.sh"
    fi
    ;;
  camera-aligner)
    if [[ -f "$PROJECT_DIR/Package.swift" ]]; then
      cd "$PROJECT_DIR"
      exec swift run CameraAligner
    fi
    ;;
  official-demos)
    if [[ -x "$PROJECT_DIR/scripts/official-demo.sh" ]]; then
      exec "$PROJECT_DIR/scripts/official-demo.sh" list
    fi
    ;;
  official-demo)
    if [[ -x "$PROJECT_DIR/scripts/official-demo.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/official-demo.sh" list
      fi
      exec "$PROJECT_DIR/scripts/official-demo.sh" "${EXTRA_ARGS[@]}"
    fi
    ;;
  xiaozhi)
    if [[ -x "$PROJECT_DIR/scripts/xiaozhi.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/xiaozhi.sh" latest
      fi
      exec "$PROJECT_DIR/scripts/xiaozhi.sh" "${EXTRA_ARGS[@]}"
    fi
    ;;
  cloud-ai)
    if [[ -x "$PROJECT_DIR/scripts/cloud-ai-terminal-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/cloud-ai-terminal-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make cloud-ai-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/cloud-ai-terminal-smoke.sh"
          ;;
        relay)
          exec python3 "$PROJECT_DIR/scripts/cloud-ai-relay.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  audio-vad)
    if [[ -x "$PROJECT_DIR/scripts/audio-vad-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/audio-vad-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make audio-vad-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/audio-vad-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/audio-vad-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
esac

CORE_VERSION="${ARDUINO_CORE_VERSION:-3.3.5}"
PACKAGE_URL="${ARDUINO_PACKAGE_URL:-https://espressif.github.io/arduino-esp32/package_esp32_index.json}"
FQBN="${ARDUINO_FQBN:-esp32:esp32:esp32s3:USBMode=hwcdc,UploadMode=default,CDCOnBoot=cdc,CPUFreq=240,FlashMode=qio,FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi,UploadSpeed=921600}"
VENDOR_DIR="${WAVESHARE_VENDOR_DIR:-$PROJECT_DIR/.vendor/ESP32-S3-Touch-AMOLED-1.75C}"
LIBRARIES="${WAVESHARE_LIBRARIES:-$VENDOR_DIR/examples/Arduino-v3.3.5/libraries}"
SKETCH="${SKETCH:-$PROJECT_DIR/sketches/codex_hello_world}"
BUILD_PATH="${BUILD_PATH:-$PROJECT_DIR/.arduino-build/codex_hello_world}"

detect_port() {
  arduino-cli board list 2>/dev/null | awk '$1 ~ /^\/dev\/cu\.usbmodem/ { print $1; found=1; exit } END { if (!found) exit 1 }'
}

PORT="${ARDUINO_PORT:-$(detect_port || true)}"

install_cli() {
  if command -v arduino-cli >/dev/null 2>&1; then
    return
  fi
  if command -v brew >/dev/null 2>&1; then
    brew install arduino-cli
  else
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR="$HOME/.local/bin" sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
}

setup_env() {
  install_cli
  arduino-cli config dump >/dev/null 2>&1 || arduino-cli config init
  if ! arduino-cli config dump | grep -Fq "$PACKAGE_URL"; then
    arduino-cli config add board_manager.additional_urls "$PACKAGE_URL"
  fi
  arduino-cli core update-index
  if ! arduino-cli core list | awk -v version="$CORE_VERSION" '$1 == "esp32:esp32" && $2 == version { found=1 } END { exit found ? 0 : 1 }'; then
    arduino-cli core install "esp32:esp32@$CORE_VERSION"
  fi
  if [[ ! -d "$LIBRARIES" ]]; then
    mkdir -p "$(dirname "$VENDOR_DIR")"
    git clone --depth 1 https://github.com/waveshareteam/ESP32-S3-Touch-AMOLED-1.75C.git "$VENDOR_DIR"
  fi
}

build_sketch() {
  setup_env
  mkdir -p "$BUILD_PATH"
  arduino-cli compile --clean --jobs 1 --fqbn "$FQBN" --libraries "$LIBRARIES" --build-path "$BUILD_PATH" "$SKETCH"
}

upload_sketch() {
  build_sketch
  if [[ -z "$PORT" ]]; then
    echo "No /dev/cu.usbmodem* port detected; set ARDUINO_PORT." >&2
    exit 1
  fi
  arduino-cli upload --fqbn "$FQBN" --port "$PORT" --build-path "$BUILD_PATH" "$SKETCH"
}

case "$ACTION" in
  setup)
    setup_env
    arduino-cli version
    arduino-cli core list
    arduino-cli board list
    ;;
  build)
    build_sketch
    ;;
  upload)
    upload_sketch
    ;;
  monitor)
    if [[ -z "$PORT" ]]; then
      echo "No /dev/cu.usbmodem* port detected; set ARDUINO_PORT." >&2
      exit 1
    fi
    if [[ "${ARDUINO_CLI_MONITOR:-0}" == "1" ]]; then
      arduino-cli monitor --port "$PORT" --fqbn "$FQBN" --config baudrate="${MONITOR_BAUD:-115200}",dtr=on,rts=off --timestamp
    else
      stty -f "$PORT" "${MONITOR_BAUD:-115200}" cs8 -cstopb -parenb -ixon -ixoff -echo
      exec cat "$PORT"
    fi
    ;;
  smoke)
    upload_sketch
    sleep 2
    PORT="${ARDUINO_PORT:-$(detect_port || printf '%s' "$PORT")}"
    stty -f "$PORT" "${MONITOR_BAUD:-115200}" cs8 -cstopb -parenb -ixon -ixoff -echo
    exec cat "$PORT"
    ;;
  visual-smoke)
    echo "No project visual smoke script found. Use a project that provides scripts/visual-smoke.sh." >&2
    exit 2
    ;;
  camera-aligner)
    echo "No SwiftPM CameraAligner found. Use this action from a repo with Package.swift." >&2
    exit 2
    ;;
  official-demos|official-demo)
    echo "No project official demo runner found. Use a project that provides scripts/official-demo.sh." >&2
    exit 2
    ;;
  xiaozhi)
    echo "No project XiaoZhi runner found. Use a project that provides scripts/xiaozhi.sh." >&2
    exit 2
    ;;
  cloud-ai)
    echo "No project cloud AI terminal runner found. Use a project that provides scripts/cloud-ai-terminal-smoke.sh." >&2
    exit 2
    ;;
  audio-vad)
    echo "No project audio VAD runner found. Use a project that provides scripts/audio-vad-smoke.sh." >&2
    exit 2
    ;;
  *)
    echo "Usage: $0 {setup|build|upload|monitor|smoke|visual-smoke|camera-aligner|official-demos|official-demo|xiaozhi|cloud-ai|audio-vad} [project-dir] [action-args...]" >&2
    exit 2
    ;;
esac
