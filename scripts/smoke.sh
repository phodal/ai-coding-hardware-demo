#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

SMOKE_SECONDS="${SMOKE_SECONDS:-8}"
mkdir -p "$LOG_DIR"

"$ROOT_DIR/scripts/upload.sh"
sleep 2

if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
  ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
fi

LOG_FILE="$LOG_DIR/smoke-$(date +%Y%m%d-%H%M%S).log"
echo "Capturing serial output from $ARDUINO_PORT for ${SMOKE_SECONDS}s -> $LOG_FILE"

set +e
arduino-cli monitor \
  --port "$ARDUINO_PORT" \
  --fqbn "$ARDUINO_FQBN" \
  --config baudrate="${MONITOR_BAUD:-115200}" \
  --timestamp >"$LOG_FILE" 2>&1 &
MONITOR_PID=$!
sleep "$SMOKE_SECONDS"
kill "$MONITOR_PID" >/dev/null 2>&1
wait "$MONITOR_PID" >/dev/null 2>&1
set -e

tail -n 40 "$LOG_FILE" || true

