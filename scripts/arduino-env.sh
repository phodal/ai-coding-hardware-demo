#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

export ARDUINO_CORE_VERSION="${ARDUINO_CORE_VERSION:-3.3.5}"
export ARDUINO_PACKAGE_URL="${ARDUINO_PACKAGE_URL:-https://espressif.github.io/arduino-esp32/package_esp32_index.json}"
export ARDUINO_FQBN="${ARDUINO_FQBN:-esp32:esp32:esp32s3:USBMode=hwcdc,UploadMode=default,CDCOnBoot=cdc,CPUFreq=240,FlashMode=qio,FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi,UploadSpeed=921600}"
export SKETCH="${SKETCH:-$ROOT_DIR/sketches/codex_hello_world}"
export BUILD_PATH="${BUILD_PATH:-$ROOT_DIR/.arduino-build/codex_hello_world}"
export LOG_DIR="${LOG_DIR:-$ROOT_DIR/.logs}"

if [[ -n "${WAVESHARE_VENDOR_DIR:-}" ]]; then
  export WAVESHARE_VENDOR_DIR
elif [[ -d "$ROOT_DIR/.vendor/ESP32-S3-Touch-AMOLED-1.75C" ]]; then
  export WAVESHARE_VENDOR_DIR="$ROOT_DIR/.vendor/ESP32-S3-Touch-AMOLED-1.75C"
elif [[ -d "/Users/phodal/Downloads/ESP32-S3-Touch-AMOLED-1.75C-main" ]]; then
  export WAVESHARE_VENDOR_DIR="/Users/phodal/Downloads/ESP32-S3-Touch-AMOLED-1.75C-main"
else
  export WAVESHARE_VENDOR_DIR="$ROOT_DIR/.vendor/ESP32-S3-Touch-AMOLED-1.75C"
fi

export WAVESHARE_ARDUINO_DIR="$WAVESHARE_VENDOR_DIR/examples/Arduino-v3.3.5"
export WAVESHARE_LIBRARIES="${WAVESHARE_LIBRARIES:-$WAVESHARE_ARDUINO_DIR/libraries}"

detect_arduino_port() {
  arduino-cli board list 2>/dev/null | awk '
    $1 ~ /^\/dev\/cu\.usbmodem/ { print $1; found=1; exit }
    END { if (!found) exit 1 }
  '
}

export ARDUINO_PORT="${ARDUINO_PORT:-$(detect_arduino_port || true)}"

require_arduino_cli() {
  if ! command -v arduino-cli >/dev/null 2>&1; then
    echo "arduino-cli is missing. Run ./scripts/setup.sh first." >&2
    exit 1
  fi
}

require_vendor_libraries() {
  if [[ ! -d "$WAVESHARE_LIBRARIES/GFX_Library_for_Arduino" ]]; then
    echo "Missing Waveshare Arduino libraries at: $WAVESHARE_LIBRARIES" >&2
    echo "Run ./scripts/setup.sh or set WAVESHARE_VENDOR_DIR." >&2
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'ROOT_DIR=%s\n' "$ROOT_DIR"
  printf 'ARDUINO_CORE_VERSION=%s\n' "$ARDUINO_CORE_VERSION"
  printf 'ARDUINO_FQBN=%s\n' "$ARDUINO_FQBN"
  printf 'ARDUINO_PORT=%s\n' "${ARDUINO_PORT:-}"
  printf 'SKETCH=%s\n' "$SKETCH"
  printf 'WAVESHARE_VENDOR_DIR=%s\n' "$WAVESHARE_VENDOR_DIR"
  printf 'WAVESHARE_LIBRARIES=%s\n' "$WAVESHARE_LIBRARIES"
  printf 'BUILD_PATH=%s\n' "$BUILD_PATH"
fi

