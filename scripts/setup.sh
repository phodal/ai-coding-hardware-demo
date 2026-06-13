#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

if ! command -v arduino-cli >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install arduino-cli
  else
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR="$HOME/.local/bin" sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

if ! arduino-cli config dump >/dev/null 2>&1; then
  arduino-cli config init
fi

if ! arduino-cli config dump | grep -Fq "$ARDUINO_PACKAGE_URL"; then
  arduino-cli config add board_manager.additional_urls "$ARDUINO_PACKAGE_URL"
fi

arduino-cli core update-index

if ! arduino-cli core list | awk -v version="$ARDUINO_CORE_VERSION" '$1 == "esp32:esp32" && $2 == version { found=1 } END { exit found ? 0 : 1 }'; then
  arduino-cli core install "esp32:esp32@$ARDUINO_CORE_VERSION"
fi

if [[ ! -d "$WAVESHARE_ARDUINO_DIR" ]]; then
  mkdir -p "$(dirname "$WAVESHARE_VENDOR_DIR")"
  git clone --depth 1 https://github.com/waveshareteam/ESP32-S3-Touch-AMOLED-1.75C.git "$WAVESHARE_VENDOR_DIR"
fi

if [[ -z "${ARDUINO_PORT:-}" ]]; then
  echo "No /dev/cu.usbmodem* port found. Connect the board and retry." >&2
  arduino-cli board list
  exit 1
fi

arduino-cli version
arduino-cli core list
arduino-cli board list
"$ROOT_DIR/scripts/arduino-env.sh"

