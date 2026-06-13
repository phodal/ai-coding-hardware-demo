#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-help}"
PROJECT_DIR="${2:-$PWD}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
EXTRA_ARGS=("${@:3}")

case "$ACTION" in
  verify|doctor)
    if [[ -f "$PROJECT_DIR/Makefile" ]]; then
      cd "$PROJECT_DIR"
      arduino-cli version
      arduino-cli core list
      arduino-cli board list
      if [[ -x "$PROJECT_DIR/scripts/official-demo.sh" ]]; then
        "$PROJECT_DIR/scripts/official-demo.sh" list
      fi
      if [[ -x "$PROJECT_DIR/scripts/xiaozhi.sh" && "${VERIFY_XIAOZHI:-0}" == "1" ]]; then
        "$PROJECT_DIR/scripts/xiaozhi.sh" inspect
      fi
      make cloud-ai-build
      make audio-vad-build
      make speaker-output-build
      make sensor-status-build
      make power-lifecycle-build
      make wifi-connectivity-build
      make touch-status-build
      make interaction-dashboard-build
      make imu-interaction-build
      make lvgl-visual-agent-build
      make desk-widget-build
      make iot-panel-build
      make offline-voice-build
      make tinyml-imu-build
      make esp-claw-agent-build
      exit 0
    fi
    ;;
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
  feature-matrix)
    if [[ -x "$PROJECT_DIR/scripts/feature-matrix-check.py" ]]; then
      cd "$PROJECT_DIR"
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec make feature-matrix-check
      fi
      case "${EXTRA_ARGS[0]}" in
        check)
          exec make feature-matrix-check
          ;;
        doc)
          exec make feature-matrix-doc
          ;;
        markdown)
          exec python3 "$PROJECT_DIR/scripts/feature-matrix-check.py" --markdown
          ;;
      esac
    fi
    ;;
  hardware-evidence)
    if [[ -x "$PROJECT_DIR/scripts/hardware-evidence-audit.py" ]]; then
      cd "$PROJECT_DIR"
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec make hardware-evidence-audit
      fi
      case "${EXTRA_ARGS[0]}" in
        audit)
          exec make hardware-evidence-audit
          ;;
        doc)
          exec make hardware-evidence-doc
          ;;
        markdown)
          exec python3 "$PROJECT_DIR/scripts/hardware-evidence-audit.py" --markdown
          ;;
      esac
    fi
    ;;
  hardware-smoke-suite)
    if [[ -x "$PROJECT_DIR/scripts/hardware-smoke-suite.py" ]]; then
      cd "$PROJECT_DIR"
      exec python3 "$PROJECT_DIR/scripts/hardware-smoke-suite.py" "${EXTRA_ARGS[@]}"
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
        pipeline)
          cd "$PROJECT_DIR"
          exec make cloud-ai-pipeline-smoke
          ;;
        cache)
          cd "$PROJECT_DIR"
          exec make cloud-ai-cache-smoke
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
        preflight)
          cd "$PROJECT_DIR"
          exec make audio-vad-preflight
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
  speaker-output)
    if [[ -x "$PROJECT_DIR/scripts/speaker-output-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/speaker-output-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make speaker-output-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/speaker-output-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/speaker-output-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  sensor-status)
    if [[ -x "$PROJECT_DIR/scripts/sensor-status-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/sensor-status-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make sensor-status-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/sensor-status-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/sensor-status-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  power-lifecycle)
    if [[ -x "$PROJECT_DIR/scripts/power-lifecycle-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/power-lifecycle-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make power-lifecycle-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/power-lifecycle-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/power-lifecycle-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  wifi-connectivity)
    if [[ -x "$PROJECT_DIR/scripts/wifi-connectivity-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/wifi-connectivity-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make wifi-connectivity-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/wifi-connectivity-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/wifi-connectivity-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  touch-status)
    if [[ -x "$PROJECT_DIR/scripts/touch-status-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/touch-status-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make touch-status-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/touch-status-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/touch-status-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  interaction-dashboard)
    if [[ -x "$PROJECT_DIR/scripts/interaction-dashboard-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/interaction-dashboard-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make interaction-dashboard-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/interaction-dashboard-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/interaction-dashboard-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  imu-interaction)
    if [[ -x "$PROJECT_DIR/scripts/imu-interaction-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/imu-interaction-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make imu-interaction-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/imu-interaction-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/imu-interaction-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  lvgl-visual-agent)
    if [[ -x "$PROJECT_DIR/scripts/lvgl-visual-agent-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/lvgl-visual-agent-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make lvgl-visual-agent-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/lvgl-visual-agent-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/lvgl-visual-agent-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  desk-widget)
    if [[ -x "$PROJECT_DIR/scripts/desk-widget-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/desk-widget-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make desk-widget-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/desk-widget-smoke.sh"
          ;;
        relay)
          cd "$PROJECT_DIR"
          exec make desk-widget-relay-smoke
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/desk-widget-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  iot-panel)
    if [[ -x "$PROJECT_DIR/scripts/iot-panel-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/iot-panel-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make iot-panel-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/iot-panel-smoke.sh"
          ;;
        relay)
          cd "$PROJECT_DIR"
          exec make iot-panel-relay-smoke
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/iot-panel-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  offline-voice)
    if [[ -x "$PROJECT_DIR/scripts/offline-voice-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/offline-voice-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make offline-voice-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/offline-voice-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/offline-voice-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  tinyml-imu)
    if [[ -x "$PROJECT_DIR/scripts/tinyml-imu-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/tinyml-imu-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make tinyml-imu-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/tinyml-imu-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/tinyml-imu-check.py" "${EXTRA_ARGS[@]:1}"
          ;;
      esac
    fi
    ;;
  esp-claw-agent)
    if [[ -x "$PROJECT_DIR/scripts/esp-claw-agent-smoke.sh" ]]; then
      if [[ "${#EXTRA_ARGS[@]}" -eq 0 ]]; then
        exec "$PROJECT_DIR/scripts/esp-claw-agent-smoke.sh"
      fi
      case "${EXTRA_ARGS[0]}" in
        build)
          cd "$PROJECT_DIR"
          exec make esp-claw-agent-build
          ;;
        smoke)
          exec "$PROJECT_DIR/scripts/esp-claw-agent-smoke.sh"
          ;;
        check)
          exec python3 "$PROJECT_DIR/scripts/esp-claw-agent-check.py" "${EXTRA_ARGS[@]:1}"
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
  verify|doctor)
    setup_env
    arduino-cli version
    arduino-cli core list
    arduino-cli board list
    build_sketch
    ;;
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
  feature-matrix)
    echo "No project feature matrix checker found. Use a project that provides scripts/feature-matrix-check.py." >&2
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
  speaker-output)
    echo "No project speaker output runner found. Use a project that provides scripts/speaker-output-smoke.sh." >&2
    exit 2
    ;;
  sensor-status)
    echo "No project sensor status runner found. Use a project that provides scripts/sensor-status-smoke.sh." >&2
    exit 2
    ;;
  power-lifecycle)
    echo "No project power lifecycle runner found. Use a project that provides scripts/power-lifecycle-smoke.sh." >&2
    exit 2
    ;;
  wifi-connectivity)
    echo "No project Wi-Fi connectivity runner found. Use a project that provides scripts/wifi-connectivity-smoke.sh." >&2
    exit 2
    ;;
  touch-status)
    echo "No project touch status runner found. Use a project that provides scripts/touch-status-smoke.sh." >&2
    exit 2
    ;;
  interaction-dashboard)
    echo "No project interaction dashboard runner found. Use a project that provides scripts/interaction-dashboard-smoke.sh." >&2
    exit 2
    ;;
  imu-interaction)
    echo "No project IMU interaction runner found. Use a project that provides scripts/imu-interaction-smoke.sh." >&2
    exit 2
    ;;
  lvgl-visual-agent)
    echo "No project LVGL visual agent runner found. Use a project that provides scripts/lvgl-visual-agent-smoke.sh." >&2
    exit 2
    ;;
  desk-widget)
    echo "No project desk widget runner found. Use a project that provides scripts/desk-widget-smoke.sh." >&2
    exit 2
    ;;
  iot-panel)
    echo "No project IoT panel runner found. Use a project that provides scripts/iot-panel-smoke.sh." >&2
    exit 2
    ;;
  offline-voice)
    echo "No project offline voice runner found. Use a project that provides scripts/offline-voice-smoke.sh." >&2
    exit 2
    ;;
  tinyml-imu)
    echo "No project TinyML IMU runner found. Use a project that provides scripts/tinyml-imu-smoke.sh." >&2
    exit 2
    ;;
  esp-claw-agent)
    echo "No project ESP-Claw agent runner found. Use a project that provides scripts/esp-claw-agent-smoke.sh." >&2
    exit 2
    ;;
  *)
    echo "Usage: $0 {setup|build|upload|monitor|smoke|verify|doctor|visual-smoke|feature-matrix|camera-aligner|official-demos|official-demo|xiaozhi|cloud-ai|audio-vad|speaker-output|sensor-status|power-lifecycle|wifi-connectivity|touch-status|interaction-dashboard|imu-interaction|lvgl-visual-agent|desk-widget|iot-panel|offline-voice|tinyml-imu|esp-claw-agent} [project-dir] [action-args...]" >&2
    exit 2
    ;;
esac
