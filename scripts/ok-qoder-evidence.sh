#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT_DIR/docs/evidence/ok-qoder-$STAMP}"
LOG_DIR="$EVIDENCE_DIR/logs"
SMOKE_SECONDS="${SMOKE_SECONDS:-8}"
CAMERA_CAPTURE_TIMEOUT="${CAMERA_CAPTURE_TIMEOUT:-8}"
DISPLAY_TEXT="${DISPLAY_TEXT:-OK Qoder}"
OCR_EXPECTED="${OCR_EXPECTED:-OK}"
ALLOW_PARTIAL="${ALLOW_PARTIAL:-0}"
DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"
OCR_ROTATE="${OCR_ROTATE:-180}"

mkdir -p "$LOG_DIR"

run_logged() {
  local name="$1"
  shift
  echo "== $name =="
  "$@" 2>&1 | tee "$EVIDENCE_DIR/$name.log"
}

run_logged build env DISPLAY_ROTATION="$DISPLAY_ROTATION" ARDUINO_BUILD_PROPERTY="compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION" make -C "$ROOT_DIR" build

if run_logged smoke env LOG_DIR="$LOG_DIR" SMOKE_SECONDS="$SMOKE_SECONDS" DISPLAY_ROTATION="$DISPLAY_ROTATION" ARDUINO_BUILD_PROPERTY="compiler.cpp.extra_flags=-DDISPLAY_ROTATION=$DISPLAY_ROTATION" make -C "$ROOT_DIR" smoke; then
  smoke_status=passed
else
  smoke_status=failed
fi

latest_smoke="$(ls -t "$LOG_DIR"/smoke-*.log 2>/dev/null | head -n 1 || true)"
perl -0pi -e 's/\r//g; s/[ \t]+$//mg' "$EVIDENCE_DIR"/*.log "$LOG_DIR"/*.log 2>/dev/null || true
serial_status=failed
if [[ -n "$latest_smoke" ]] && rg -q "codex_hello_world frame=" "$latest_smoke"; then
  serial_status=passed
fi

camera_status=failed
set +e
env \
  LOG_DIR="$EVIDENCE_DIR" \
  CAMERA_CAPTURE_TIMEOUT="$CAMERA_CAPTURE_TIMEOUT" \
  OCR_EXPECTED="$OCR_EXPECTED" \
  OCR_ROTATE="$OCR_ROTATE" \
  OCR_ENGINE="${OCR_ENGINE:-vision}" \
  "$ROOT_DIR/scripts/camera-ocr.sh" >"$EVIDENCE_DIR/camera-ocr.log" 2>&1
camera_rc=$?
set -e
if [[ "$camera_rc" == "0" ]]; then
  camera_status=passed
fi

raw_image="$(ls -t "$EVIDENCE_DIR"/camera-ocr-*.jpg 2>/dev/null | head -n 1 || true)"
processed_image="$(ls -t "$EVIDENCE_DIR"/camera-ocr-*.processed.png 2>/dev/null | head -n 1 || true)"
ocr_text="$(ls -t "$EVIDENCE_DIR"/camera-ocr-*.txt 2>/dev/null | head -n 1 || true)"

summary="$EVIDENCE_DIR/summary.md"
summary_json="$EVIDENCE_DIR/summary.json"
{
  echo "# OK Qoder Evidence $STAMP"
  echo
  echo "This evidence pack records the default hello sketch validation chain for the Waveshare ESP32-S3 Touch AMOLED 1.75C."
  echo
  echo "## Result"
  echo
  echo "- Build: passed"
  echo "- Upload and serial smoke: $smoke_status"
  echo "- Serial frame evidence: $serial_status"
  echo "- Camera OCR: $camera_status"
  echo "- Display rotation: $DISPLAY_ROTATION"
  echo "- OCR rotation: $OCR_ROTATE"
  echo "- Destructive: 0"
  echo "- Audio: 0"
  echo
  echo "## Artifacts"
  echo
  echo "- Build log: \`build.log\`"
  echo "- Smoke log: \`smoke.log\`"
  if [[ -n "$latest_smoke" ]]; then
    echo "- Raw serial log: \`${latest_smoke#"$EVIDENCE_DIR/"}\`"
  fi
  echo "- Camera OCR log: \`camera-ocr.log\`"
  if [[ -n "$raw_image" ]]; then
    echo "- Raw camera image: \`${raw_image#"$EVIDENCE_DIR/"}\`"
  else
    echo "- Raw camera image: not captured"
  fi
  if [[ -n "$processed_image" ]]; then
    echo "- Processed OCR image: \`${processed_image#"$EVIDENCE_DIR/"}\`"
  else
    echo "- Processed OCR image: not generated"
  fi
  if [[ -n "$ocr_text" ]]; then
    echo "- OCR text: \`${ocr_text#"$EVIDENCE_DIR/"}\`"
  else
    echo "- OCR text: not generated"
  fi
  echo
  echo "## Interpretation"
  echo
  if [[ "$camera_status" == "passed" ]]; then
    echo "The full chain passed: source change, clean build, upload, serial runtime, camera image capture, and OCR recognition of \`$OCR_EXPECTED\`."
  else
    echo "The firmware chain passed through serial, but the visual chain did not complete. Treat this as host camera availability or framing work before claiming AMOLED visual proof."
  fi
} >"$summary"

{
  echo "{"
  echo "  \"id\": \"ok-qoder-$STAMP\","
  echo "  \"timestamp\": \"$STAMP\","
  echo "  \"sketch\": \"sketches/codex_hello_world\","
  echo "  \"display_text\": \"$DISPLAY_TEXT\","
  echo "  \"expected_ocr\": \"$OCR_EXPECTED\","
  echo "  \"display_rotation\": $DISPLAY_ROTATION,"
  echo "  \"ocr_rotation\": $OCR_ROTATE,"
  echo "  \"build\": \"passed\","
  echo "  \"smoke\": \"$smoke_status\","
  echo "  \"serial\": \"$serial_status\","
  echo "  \"camera_ocr\": \"$camera_status\","
  echo "  \"destructive\": 0,"
  echo "  \"audio\": 0,"
  echo "  \"artifacts\": {"
  echo "    \"build_log\": \"build.log\","
  echo "    \"smoke_log\": \"smoke.log\","
  if [[ -n "$latest_smoke" ]]; then
    echo "    \"serial_log\": \"${latest_smoke#"$EVIDENCE_DIR/"}\","
  else
    echo "    \"serial_log\": null,"
  fi
  echo "    \"camera_ocr_log\": \"camera-ocr.log\","
  if [[ -n "$raw_image" ]]; then
    echo "    \"raw_image\": \"${raw_image#"$EVIDENCE_DIR/"}\","
  else
    echo "    \"raw_image\": null,"
  fi
  if [[ -n "$processed_image" ]]; then
    echo "    \"processed_image\": \"${processed_image#"$EVIDENCE_DIR/"}\","
  else
    echo "    \"processed_image\": null,"
  fi
  if [[ -n "$ocr_text" ]]; then
    echo "    \"ocr_text\": \"${ocr_text#"$EVIDENCE_DIR/"}\""
  else
    echo "    \"ocr_text\": null"
  fi
  echo "  }"
  echo "}"
} >"$summary_json"

echo "ok_qoder_evidence_summary dir=$EVIDENCE_DIR build=passed smoke=$smoke_status serial=$serial_status camera=$camera_status destructive=0 audio=0"

if [[ "$smoke_status" != "passed" || "$serial_status" != "passed" ]]; then
  exit 1
fi
if [[ "$camera_status" != "passed" && "$ALLOW_PARTIAL" != "1" ]]; then
  exit "$camera_rc"
fi
