#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

MANIFEST="${OFFICIAL_DEMO_MANIFEST:-$ROOT_DIR/config/official-demos.tsv}"
ACTION="${1:-list}"
DEMO_ID="${2:-}"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/official-demo.sh list
  scripts/official-demo.sh path <demo-id>
  scripts/official-demo.sh build <demo-id>
  scripts/official-demo.sh upload <demo-id>
  scripts/official-demo.sh smoke <demo-id>
  scripts/official-demo.sh build-all
EOF
}

read_demo() {
  local wanted="$1"
  awk -F '\t' -v wanted="$wanted" '
    $0 !~ /^#/ && NF >= 5 && $1 == wanted { print; found=1; exit }
    END { if (!found) exit 1 }
  ' "$MANIFEST"
}

demo_ids() {
  awk -F '\t' '$0 !~ /^#/ && NF >= 5 { print $1 }' "$MANIFEST"
}

configure_demo() {
  local row id category title sketch_rel expected notes source_dir stage_dir ino_files ino_file main_ino
  row="$(read_demo "$1")" || {
    echo "Unknown official demo: $1" >&2
    echo "Known demos:" >&2
    demo_ids >&2
    exit 2
  }

  IFS=$'\t' read -r id category title sketch_rel expected notes <<<"$row"

  export OFFICIAL_DEMO_ID="$id"
  export OFFICIAL_DEMO_CATEGORY="$category"
  export OFFICIAL_DEMO_TITLE="$title"
  export OFFICIAL_DEMO_EXPECTED_SERIAL="$expected"
  source_dir="$WAVESHARE_ARDUINO_DIR/examples/$sketch_rel"
  stage_dir="$ROOT_DIR/.arduino-build/official-sketches/$id"
  export OFFICIAL_DEMO_SOURCE_SKETCH="$source_dir"
  export SKETCH="$stage_dir"
  export BUILD_PATH="$ROOT_DIR/.arduino-build/official-$id"

  if [[ ! -d "$source_dir" ]]; then
    echo "Official demo sketch directory does not exist: $source_dir" >&2
    exit 1
  fi

  rm -rf "$stage_dir"
  mkdir -p "$stage_dir"
  cp -R "$source_dir/." "$stage_dir/"

  shopt -s nullglob
  ino_files=("$stage_dir"/*.ino)
  shopt -u nullglob
  if [[ "${#ino_files[@]}" -ne 1 ]]; then
    echo "Expected exactly one .ino file in official demo: $source_dir" >&2
    exit 1
  fi

  ino_file="${ino_files[0]}"
  main_ino="$stage_dir/$(basename "$stage_dir").ino"
  if [[ "$ino_file" != "$main_ino" ]]; then
    mv "$ino_file" "$main_ino"
  fi
}

list_demos() {
  printf '%-20s %-10s %-30s %s\n' "ID" "CATEGORY" "TITLE" "SKETCH"
  awk -F '\t' '
    $0 !~ /^#/ && NF >= 5 {
      printf "%-20s %-10s %-30s %s\n", $1, $2, $3, $4
    }
  ' "$MANIFEST"
}

capture_serial() {
  local log_file expected
  expected="$1"
  mkdir -p "$LOG_DIR"

  if [[ -z "${ARDUINO_PORT_PINNED:-}" ]]; then
    ARDUINO_PORT="$(detect_arduino_port || printf '%s' "$ARDUINO_PORT")"
  fi

  log_file="$LOG_DIR/official-$OFFICIAL_DEMO_ID-$(date +%Y%m%d-%H%M%S).log"
  echo "Capturing serial output from $ARDUINO_PORT for ${SMOKE_SECONDS:-8}s -> $log_file"

  set +e
  if [[ "${ARDUINO_CLI_MONITOR:-0}" == "1" ]]; then
    arduino-cli monitor \
      --port "$ARDUINO_PORT" \
      --fqbn "$ARDUINO_FQBN" \
      --config baudrate="${MONITOR_BAUD:-115200}",dtr=on,rts=off \
      --timestamp >"$log_file" 2>&1 &
  else
    stty -f "$ARDUINO_PORT" "${MONITOR_BAUD:-115200}" cs8 -cstopb -parenb -ixon -ixoff -echo
    cat "$ARDUINO_PORT" >"$log_file" 2>&1 &
  fi
  local monitor_pid=$!
  sleep "${SMOKE_SECONDS:-8}"
  kill "$monitor_pid" >/dev/null 2>&1
  wait "$monitor_pid" >/dev/null 2>&1
  set -e

  tail -n 40 "$log_file" || true
  if [[ "$expected" != "-" ]] && ! rg -F "$expected" "$log_file" >/dev/null; then
    echo "Expected serial text not found for $OFFICIAL_DEMO_ID: $expected" >&2
    exit 1
  fi
}

case "$ACTION" in
  list)
    list_demos
    ;;
  path)
    [[ -n "$DEMO_ID" ]] || { usage; exit 2; }
    configure_demo "$DEMO_ID"
    printf '%s\n' "$SKETCH"
    ;;
  build)
    [[ -n "$DEMO_ID" ]] || { usage; exit 2; }
    configure_demo "$DEMO_ID"
    "$ROOT_DIR/scripts/build.sh"
    ;;
  upload)
    [[ -n "$DEMO_ID" ]] || { usage; exit 2; }
    configure_demo "$DEMO_ID"
    "$ROOT_DIR/scripts/upload.sh"
    ;;
  smoke)
    [[ -n "$DEMO_ID" ]] || { usage; exit 2; }
    configure_demo "$DEMO_ID"
    "$ROOT_DIR/scripts/upload.sh"
    sleep "${OFFICIAL_SMOKE_SETTLE_SECONDS:-0}"
    capture_serial "$OFFICIAL_DEMO_EXPECTED_SERIAL"
    ;;
  build-all)
    failed=0
    while IFS= read -r id; do
      echo "==> Building official demo: $id"
      if ! "$0" build "$id"; then
        failed=1
      fi
    done < <(demo_ids)
    exit "$failed"
    ;;
  *)
    usage
    exit 2
    ;;
esac
