#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

if [[ -z "${WIFI_TEST_SSID:-}" || -z "${WIFI_TEST_PASSWORD:-}" ]]; then
  echo "WIFI_TEST_SSID and WIFI_TEST_PASSWORD must be set in the ignored .env file or environment." >&2
  exit 2
fi

export SKETCH="${WEB_AI_BUTTON_SKETCH:-$ROOT_DIR/sketches/web_ai_button}"
export BUILD_PATH="${WEB_AI_BUTTON_BUILD_PATH:-$ROOT_DIR/.arduino-build/web_ai_button}"
export DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
export ARDUINO_BUILD_PROPERTY="${ARDUINO_BUILD_PROPERTY:-compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION}"

SERVER_HOST="${WEB_AI_SERVER_HOST:-0.0.0.0}"
SERVER_PORT="${WEB_AI_SERVER_PORT:-8787}"
SERVER_MODE="${WEB_AI_SERVER_MODE:-mock}"
SERVER_LOG="${LOG_DIR:-$ROOT_DIR/.logs}/web-ai-server.log"
mkdir -p "$(dirname "$SERVER_LOG")"

host_ip="${WEB_AI_HOST_IP:-}"
if [[ -z "$host_ip" ]]; then
  host_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi
if [[ -z "$host_ip" ]]; then
  host_ip="$(ipconfig getifaddr en1 2>/dev/null || true)"
fi
if [[ -z "$host_ip" ]]; then
  host_ip="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}' | xargs -I{} ipconfig getifaddr {} 2>/dev/null || true)"
fi
if [[ -z "$host_ip" ]]; then
  echo "Could not determine a LAN host IP. Set WEB_AI_HOST_IP to the Mac address reachable from the ESP32." >&2
  exit 2
fi

python3 "$ROOT_DIR/scripts/local-ai-webserver.py" \
  --host "$SERVER_HOST" \
  --port "$SERVER_PORT" \
  --mode "$SERVER_MODE" \
  >"$SERVER_LOG" 2>&1 &
server_pid=$!
cleanup() {
  kill "$server_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep "${WEB_AI_SERVER_SETTLE_SECONDS:-0.5}"
python3 - <<PY
import json
import urllib.request
with urllib.request.urlopen("http://127.0.0.1:${SERVER_PORT}/health", timeout=5) as response:
    payload = json.load(response)
assert payload.get("ok") is True, payload
PY

"$ROOT_DIR/scripts/upload.sh"
sleep "${WEB_AI_SETTLE_SECONDS:-1}"

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  export ARDUINO_PORT
fi

python3 "$ROOT_DIR/scripts/web-ai-button-check.py" \
  --port "$ARDUINO_PORT" \
  --baud "${MONITOR_BAUD:-115200}" \
  --ssid "$WIFI_TEST_SSID" \
  --password "$WIFI_TEST_PASSWORD" \
  --endpoint "http://$host_ip:$SERVER_PORT/ask" \
  --question "${WEB_AI_QUESTION:-touch button}" \
  --expect "${WEB_AI_EXPECT:-AI OK}" \
  --timeout "${WEB_AI_TIMEOUT:-40}"

if [[ "${WEB_AI_BUTTON_VISUAL_SMOKE:-0}" == "1" ]]; then
  OCR_EXPECTED="${WEB_AI_BUTTON_OCR_EXPECTED:-AI}" "$ROOT_DIR/scripts/camera-ocr.sh"
fi
