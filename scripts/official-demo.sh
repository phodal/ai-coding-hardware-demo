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
  scripts/official-demo.sh audio-preflight
  scripts/official-demo.sh audio-physical-plan
  scripts/official-demo.sh audio-physical-smoke
  scripts/official-demo.sh coverage
EOF
}

patch_power_wifi_timeout() {
  local ino_file="$1"
  local timeout_ms="${OFFICIAL_POWER_WIFI_TIMEOUT_MS:-5000}"

  python3 - "$ino_file" "$timeout_ms" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
timeout_ms = int(sys.argv[2])
text = path.read_text()
old = """  WiFi.begin(ssid_sta, password_sta);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\\nStation模式连接成功！");
  Serial.print("Station模式IP地址: ");
  Serial.println(WiFi.localIP());
"""
new = f"""  WiFi.begin(ssid_sta, password_sta);
  uint32_t wifi_start_ms = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - wifi_start_ms) < {timeout_ms}UL) {{
    delay(500);
    Serial.print(".");
  }}
  if (WiFi.status() == WL_CONNECTED) {{
    Serial.println("\\nStation模式连接成功！");
    Serial.print("Station模式IP地址: ");
    Serial.println(WiFi.localIP());
  }} else {{
    Serial.println("\\nOFFICIAL_POWER_WIFI_TIMEOUT continuing PMU/LVGL smoke");
  }}
"""
if old not in text:
    raise SystemExit(f"Expected Wi-Fi wait block not found in {path}")
path.write_text(text.replace(old, new))
PY
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

audio_demo_ids() {
  awk -F '\t' '$0 !~ /^#/ && NF >= 5 && $2 ~ /^audio/ { print $1 }' "$MANIFEST"
}

demo_rows() {
  awk -F '\t' '$0 !~ /^#/ && NF >= 5 { print }' "$MANIFEST"
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

  if [[ "$id" == "03-power-axp2101" ]]; then
    patch_power_wifi_timeout "$main_ino"
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

check_audio_markers() {
  local id="$1" category="$2" expected="$3" source_dir="$4"
  local marker_pattern
  case "$category" in
    audio-in)
      marker_pattern='ES7210|Speech detected|VAD|I2S'
      ;;
    audio-out)
      marker_pattern='ES8311|Echo start|I2S|codec'
      ;;
    *)
      echo "Unsupported audio category for $id: $category" >&2
      exit 1
      ;;
  esac

  if [[ "$expected" == "-" ]]; then
    echo "Audio demo $id is missing an expected serial marker." >&2
    exit 1
  fi
  if ! rg -n "$marker_pattern" "$source_dir" >/dev/null; then
    echo "Audio demo $id is missing expected source markers: $marker_pattern" >&2
    exit 1
  fi
}

audio_preflight() {
  local failed=0 count=0 row id category title sketch_rel expected notes
  while IFS= read -r id; do
    row="$(read_demo "$id")"
    IFS=$'\t' read -r id category title sketch_rel expected notes <<<"$row"
    configure_demo "$id"
    check_audio_markers "$id" "$category" "$expected" "$OFFICIAL_DEMO_SOURCE_SKETCH"
    echo "==> Audio preflight build: $id ($title)"
    if "$ROOT_DIR/scripts/build.sh"; then
      echo "official_audio_preflight id=$id category=$category expected=${expected// /_} status=passed destructive=0 audio=0"
    else
      failed=1
      echo "official_audio_preflight id=$id category=$category expected=${expected// /_} status=failed destructive=0 audio=0"
    fi
    count=$((count + 1))
  done < <(audio_demo_ids)

  echo "official_audio_preflight_summary demos=$count failed=$failed destructive=0 audio=0"
  exit "$failed"
}

audio_physical_plan() {
  local count=0 row id category title sketch_rel expected notes command
  while IFS= read -r id; do
    row="$(read_demo "$id")"
    IFS=$'\t' read -r id category title sketch_rel expected notes <<<"$row"
    case "$category" in
      audio-in)
        command="ALLOW_AUDIO=1 make official-audio-physical-smoke"
        ;;
      audio-out)
        command="ALLOW_AUDIO=1 OFFICIAL_AUDIO_OUTPUT_CONFIRM=heard make official-audio-physical-smoke"
        ;;
      *)
        command="-"
        ;;
    esac
    printf 'official_audio_physical_plan id=%s category=%s title=%q expected=%q command=%q requires_allowed_audio=1 destructive=requires_upload audio=physical\n' \
      "$id" "$category" "$title" "$expected" "$command"
    count=$((count + 1))
  done < <(audio_demo_ids)

  printf 'official_audio_physical_plan_summary demos=%s destructive=requires_upload audio=physical gated_by=ALLOW_AUDIO\n' "$count"
}

capture_serial_with_stimulus() {
  local expected="$1" capture_pid
  capture_serial "$expected" &
  capture_pid=$!
  sleep "${OFFICIAL_AUDIO_STIMULUS_DELAY:-2}"
  echo "> stimulus: ${OFFICIAL_AUDIO_STIMULUS_COMMAND:-say 'hello xiao zhi official audio input test'}"
  eval "${OFFICIAL_AUDIO_STIMULUS_COMMAND:-say 'hello xiao zhi official audio input test'}"
  wait "$capture_pid"
}

audio_physical_smoke() {
  if [[ "${ALLOW_AUDIO:-0}" != "1" ]]; then
    echo "official_audio_physical_smoke status=refused reason=allow_audio_required hint='set ALLOW_AUDIO=1 during an allowed audio window' destructive=0 audio=0" >&2
    return 2
  fi

  local failed=0 count=0 row id category title sketch_rel expected notes
  while IFS= read -r id; do
    row="$(read_demo "$id")"
    IFS=$'\t' read -r id category title sketch_rel expected notes <<<"$row"
    configure_demo "$id"
    check_audio_markers "$id" "$category" "$expected" "$OFFICIAL_DEMO_SOURCE_SKETCH"
    echo "==> Official audio physical smoke: $id ($title)"
    "$ROOT_DIR/scripts/upload.sh"
    sleep "${OFFICIAL_SMOKE_SETTLE_SECONDS:-0}"
    case "$category" in
      audio-in)
        if capture_serial_with_stimulus "$expected"; then
          echo "official_audio_physical_smoke id=$id category=$category status=passed destructive=1 audio=physical"
        else
          failed=1
          echo "official_audio_physical_smoke id=$id category=$category status=failed destructive=1 audio=physical"
        fi
        ;;
      audio-out)
        if capture_serial "$expected"; then
          if [[ "${OFFICIAL_AUDIO_OUTPUT_CONFIRM:-}" == "heard" ]]; then
            echo "official_audio_physical_smoke id=$id category=$category status=passed audible_confirmed=1 destructive=1 audio=physical"
          else
            failed=1
            echo "official_audio_physical_smoke id=$id category=$category status=failed audible_confirmed=0 reason=manual_audible_confirmation_required destructive=1 audio=physical"
          fi
        else
          failed=1
          echo "official_audio_physical_smoke id=$id category=$category status=failed reason=serial_marker_missing destructive=1 audio=physical"
        fi
        ;;
      *)
        failed=1
        echo "official_audio_physical_smoke id=$id category=$category status=failed reason=unsupported_category destructive=0 audio=0"
        ;;
    esac
    count=$((count + 1))
  done < <(audio_demo_ids)

  echo "official_audio_physical_smoke_summary demos=$count failed=$failed destructive=1 audio=physical"
  return "$failed"
}

latest_matching_smoke_log() {
  local id="$1" expected="$2" log
  [[ "$expected" != "-" ]] || return 1
  [[ -d "$ROOT_DIR/.logs" ]] || return 1
  while IFS= read -r log; do
    if rg -F "$expected" "$log" >/dev/null; then
      printf '%s\n' "$log"
      return 0
    fi
  done < <(find "$ROOT_DIR/.logs" -type f -name "official-$id-*.log" 2>/dev/null | sort -r)
  return 1
}

coverage_audit() {
  local total=0 built=0 physical=0 audio=0 audio_quiet_ready=0 missing_physical=0
  local row id category title sketch_rel expected notes build_bin build_status build_bytes
  local source_dir source_status audio_quiet_status smoke_log smoke_status completion

  while IFS= read -r row; do
    IFS=$'\t' read -r id category title sketch_rel expected notes <<<"$row"
    total=$((total + 1))
    build_bin="$ROOT_DIR/.arduino-build/official-$id/$id.ino.bin"
    if [[ -f "$build_bin" ]]; then
      build_status="passed"
      build_bytes="$(stat -f %z "$build_bin")"
      built=$((built + 1))
    else
      build_status="missing"
      build_bytes=0
    fi

    source_dir="$WAVESHARE_ARDUINO_DIR/examples/$sketch_rel"
    source_status="present"
    [[ -d "$source_dir" ]] || source_status="missing"

    audio_quiet_status="not_required"
    if [[ "$category" == audio-* ]]; then
      audio=$((audio + 1))
      if [[ "$source_status" == "present" ]] && ( check_audio_markers "$id" "$category" "$expected" "$source_dir" ); then
        audio_quiet_status="marker_ready"
        audio_quiet_ready=$((audio_quiet_ready + 1))
      else
        audio_quiet_status="missing_markers"
      fi
    fi

    if smoke_log="$(latest_matching_smoke_log "$id" "$expected")"; then
      smoke_status="passed"
      physical=$((physical + 1))
    else
      smoke_status="missing"
      smoke_log="-"
      missing_physical=$((missing_physical + 1))
    fi

    completion="physical-required"
    if [[ "$smoke_status" == "passed" && "$category" != audio-* ]]; then
      completion="non-audio-physical-passed"
    elif [[ "$smoke_status" == "passed" ]]; then
      completion="audio-physical-passed"
    elif [[ "$category" == audio-* && "$audio_quiet_status" == "marker_ready" && "$build_status" == "passed" ]]; then
      completion="quiet-preflight-only"
    elif [[ "$build_status" == "passed" ]]; then
      completion="build-only"
    fi

    printf 'official_coverage id=%s category=%s build=%s build_bytes=%s source=%s audio_quiet=%s physical_smoke=%s log=%s completion=%s destructive=0 audio=0\n' \
      "$id" "$category" "$build_status" "$build_bytes" "$source_status" "$audio_quiet_status" "$smoke_status" "$smoke_log" "$completion"
  done < <(demo_rows)

  printf 'official_coverage_summary demos=%s built=%s physical_smoke=%s missing_physical=%s audio_demos=%s audio_quiet_ready=%s destructive=0 audio=0\n' \
    "$total" "$built" "$physical" "$missing_physical" "$audio" "$audio_quiet_ready"
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

  if [[ "${OFFICIAL_SERIAL_CAPTURE_PY:-1}" == "1" ]]; then
    local capture_args=()
    if [[ "${OFFICIAL_CAPTURE_PULSE_RESET:-1}" == "1" ]]; then
      capture_args+=(--pulse-rts)
    fi
    python3 "$ROOT_DIR/scripts/serial-capture.py" \
      --port "$ARDUINO_PORT" \
      --baud "${MONITOR_BAUD:-115200}" \
      --seconds "${SMOKE_SECONDS:-8}" \
      --log "$log_file" \
      --expect "$expected" \
      "${capture_args[@]}"
    return
  fi

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
  audio-preflight)
    audio_preflight
    ;;
  audio-physical-plan)
    audio_physical_plan
    ;;
  audio-physical-smoke)
    audio_physical_smoke
    ;;
  coverage)
    coverage_audit
    ;;
  *)
    usage
    exit 2
    ;;
esac
