#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/arduino-env.sh"

ACTION="${1:-help}"
XIAOZHI_BOARD_SLUG="${XIAOZHI_BOARD_SLUG:-waveshare-esp32-s3-touch-amoled-1.75c}"
XIAOZHI_RELEASE_REPO="${XIAOZHI_RELEASE_REPO:-78/xiaozhi-esp32}"
XIAOZHI_SOURCE_REPO="${XIAOZHI_SOURCE_REPO:-https://github.com/78/xiaozhi-esp32.git}"
XIAOZHI_WORK_DIR="${XIAOZHI_WORK_DIR:-$ROOT_DIR/.vendor/xiaozhi}"
XIAOZHI_SOURCE_DIR="${XIAOZHI_SOURCE_DIR:-$XIAOZHI_WORK_DIR/source}"
XIAOZHI_FIRMWARE_DIR="${XIAOZHI_FIRMWARE_DIR:-$XIAOZHI_WORK_DIR/firmware}"
XIAOZHI_FLASH_ADDRESS="${XIAOZHI_FLASH_ADDRESS:-0x0}"
XIAOZHI_BAUD="${XIAOZHI_BAUD:-921600}"
XIAOZHI_SDKCONFIG_DEFAULTS="${XIAOZHI_SDKCONFIG_DEFAULTS:-sdkconfig.defaults;sdkconfig.defaults.esp32s3;$ROOT_DIR/config/xiaozhi-sdkconfig.defaults}"
XIAOZHI_IDF_PATH="${XIAOZHI_IDF_PATH:-$ROOT_DIR/.vendor/esp-idf-v5.5.4}"
XIAOZHI_IDF_PYTHON_ENV_PATH="${XIAOZHI_IDF_PYTHON_ENV_PATH:-}"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/xiaozhi.sh latest
  scripts/xiaozhi.sh download
  scripts/xiaozhi.sh inspect
  scripts/xiaozhi.sh preflight
  scripts/xiaozhi.sh flash --yes
  scripts/xiaozhi.sh erase --yes
  scripts/xiaozhi.sh source-clone
  scripts/xiaozhi.sh source-check
  scripts/xiaozhi.sh idf-env
  scripts/xiaozhi.sh idf-build
  scripts/xiaozhi.sh idf-flash
  scripts/xiaozhi.sh idf-monitor
EOF
}

require_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required." >&2
    exit 1
  fi
}

require_port() {
  if [[ -z "${ARDUINO_PORT:-}" ]]; then
    echo "No serial port detected. Set ARDUINO_PORT or reconnect the board." >&2
    arduino-cli board list || true
    exit 1
  fi
}

require_yes() {
  if [[ "${1:-}" != "--yes" ]]; then
    echo "This action flashes or erases the board. Re-run with --yes when ready." >&2
    exit 2
  fi
}

detect_idf_python_env() {
  if [[ -n "$XIAOZHI_IDF_PYTHON_ENV_PATH" ]]; then
    printf '%s\n' "$XIAOZHI_IDF_PYTHON_ENV_PATH"
    return
  fi

  local idf_version idf_minor env_dir
  idf_version="$(basename "$XIAOZHI_IDF_PATH" | sed -n 's/.*v\([0-9][0-9.]*\).*/\1/p')"
  idf_minor="${idf_version%.*}"
  env_dir="$(find "$HOME/.espressif/python_env" -maxdepth 1 -type d -name "idf${idf_minor}_py*_env" 2>/dev/null | sort | tail -n 1 || true)"
  if [[ -n "$env_dir" && -x "$env_dir/bin/python" ]]; then
    printf '%s\n' "$env_dir"
  fi
}

source_idf() {
  local mode="${1:-optional}"
  if command -v idf.py >/dev/null 2>&1; then
    return 0
  fi

  local export_script="$XIAOZHI_IDF_PATH/export.sh"
  if [[ ! -f "$export_script" ]]; then
    if [[ "$mode" == "required" ]]; then
      echo "ESP-IDF export script is missing: $export_script" >&2
      echo "Install ESP-IDF v5.5.x or set XIAOZHI_IDF_PATH before building XiaoZhi from source." >&2
      exit 1
    fi
    return 1
  fi

  local python_env
  python_env="$(detect_idf_python_env || true)"
  if [[ -n "$python_env" ]]; then
    export IDF_PYTHON_ENV_PATH="$python_env"
  fi

  # shellcheck disable=SC1090
  if source "$export_script" >/tmp/xiaozhi-idf-export.log 2>&1; then
    return 0
  fi

  if [[ "$mode" == "required" ]]; then
    echo "Failed to activate ESP-IDF from $export_script." >&2
    echo "See /tmp/xiaozhi-idf-export.log for the ESP-IDF export output." >&2
    exit 1
  fi
  return 1
}

find_esptool() {
  if command -v esptool.py >/dev/null 2>&1; then
    command -v esptool.py
    return
  fi

  if command -v esptool >/dev/null 2>&1; then
    command -v esptool
    return
  fi

  local arduino_esptool
  arduino_esptool="$(find "$HOME/Library/Arduino15/packages/esp32/tools/esptool_py" -type f -name esptool 2>/dev/null | sort -V | tail -n 1 || true)"
  if [[ -n "$arduino_esptool" ]]; then
    printf '%s\n' "$arduino_esptool"
    return
  fi

  echo "esptool is missing. Install esp32 core with arduino-cli or install esptool.py." >&2
  exit 1
}

latest_asset_json() {
  require_python
  python3 - "$XIAOZHI_RELEASE_REPO" "$XIAOZHI_BOARD_SLUG" <<'PY'
import json
import sys
import urllib.request

repo, slug = sys.argv[1], sys.argv[2]
url = f"https://api.github.com/repos/{repo}/releases/latest"
with urllib.request.urlopen(url, timeout=30) as response:
    release = json.load(response)

suffix = f"_{slug}.zip"
for asset in release.get("assets", []):
    if asset.get("name", "").endswith(suffix):
        print(json.dumps({
            "tag": release.get("tag_name"),
            "release_name": release.get("name"),
            "asset_name": asset.get("name"),
            "download_url": asset.get("browser_download_url"),
            "size": asset.get("size"),
        }, ensure_ascii=True))
        break
else:
    names = [asset.get("name") for asset in release.get("assets", [])]
    raise SystemExit(f"No asset ending with {suffix!r}. Release assets: {names}")
PY
}

asset_field() {
  latest_asset_json | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"
}

firmware_zip_path() {
  mkdir -p "$XIAOZHI_FIRMWARE_DIR"
  printf '%s/%s\n' "$XIAOZHI_FIRMWARE_DIR" "$(asset_field asset_name)"
}

download_firmware() {
  local zip_path url
  zip_path="$(firmware_zip_path)"
  url="$(asset_field download_url)"
  if [[ ! -f "$zip_path" ]]; then
    echo "Downloading $url -> $zip_path" >&2
    curl -fL "$url" -o "$zip_path"
  fi
  printf '%s\n' "$zip_path"
}

inspect_firmware() {
  local zip_path
  zip_path="$(download_firmware)"
  unzip -l "$zip_path"
  if ! unzip -l "$zip_path" | awk '{ print $4 }' | rg '^merged-binary\.bin$' >/dev/null; then
    echo "Expected merged-binary.bin inside $zip_path." >&2
    exit 1
  fi
  python3 - "$zip_path" <<'PY'
import hashlib
import pathlib
import sys
import zipfile

zip_path = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(zip_path) as archive:
    merged = archive.read("merged-binary.bin")

print(
    "xiaozhi_firmware_summary "
    f"zip={zip_path} zip_size={zip_path.stat().st_size} "
    f"merged_size={len(merged)} merged_sha256={hashlib.sha256(merged).hexdigest()}"
)
PY
}

preflight() {
  local esptool source_status idf_status latest_json
  latest_json="$(latest_asset_json)"
  inspect_firmware
  esptool="$(find_esptool)"

  if [[ -d "$XIAOZHI_SOURCE_DIR/.git" ]]; then
    source_status="$(git -C "$XIAOZHI_SOURCE_DIR" describe --tags --always 2>/dev/null || git -C "$XIAOZHI_SOURCE_DIR" rev-parse --short HEAD)"
    if ! rg -q "CONFIG_BOARD_TYPE_WAVESHARE_ESP32_S3_TOUCH_AMOLED_1_75C" "$XIAOZHI_SOURCE_DIR" "$ROOT_DIR/config/xiaozhi-sdkconfig.defaults"; then
      echo "XiaoZhi source is present but board config marker was not found." >&2
      exit 1
    fi
  else
    source_status="missing"
  fi

  source_idf optional || true
  if command -v idf.py >/dev/null 2>&1; then
    idf_status="$(command -v idf.py)"
  else
    idf_status="missing"
  fi

  python3 - "$latest_json" "$XIAOZHI_BOARD_SLUG" "$ARDUINO_PORT" "$esptool" "$source_status" "$idf_status" <<'PY'
import json
import sys

latest = json.loads(sys.argv[1])
print(
    "xiaozhi_preflight_summary "
    f"tag={latest['tag']} asset={latest['asset_name']} asset_size={latest['size']} "
    f"slug={sys.argv[2]} port={sys.argv[3] or 'missing'} esptool={sys.argv[4]} "
    f"source={sys.argv[5]} idf={sys.argv[6]} destructive=0 audio=0"
)
PY
}

idf_env_summary() {
  source_idf required
  local idf_path idf_py idf_version
  idf_path="${IDF_PATH:-$XIAOZHI_IDF_PATH}"
  idf_py="${IDF_PYTHON_ENV_PATH:-missing}"
  idf_version="$(idf.py --version 2>/dev/null | tr ' ' '_')"
  printf 'xiaozhi_idf_summary idf=%s path=%s python_env=%s destructive=0 audio=0\n' \
    "$idf_version" "$idf_path" "$idf_py"
}

prepare_idf_build_dir() {
  local build_dir="$XIAOZHI_SOURCE_DIR/build"
  if [[ -d "$build_dir" && ! -f "$build_dir/CMakeCache.txt" ]]; then
    echo "Removing incomplete XiaoZhi IDF build directory: $build_dir" >&2
    rm -rf "$build_dir"
  fi
}

idf_build_summary() {
  local build_dir="$XIAOZHI_SOURCE_DIR/build"
  local app_bin="$build_dir/xiaozhi.bin"
  local bootloader_bin="$build_dir/bootloader/bootloader.bin"
  local partition_bin="$build_dir/partition_table/partition-table.bin"
  local assets_bin="$build_dir/generated_assets.bin"
  if [[ ! -f "$app_bin" ]]; then
    echo "Expected XiaoZhi app binary after build: $app_bin" >&2
    exit 1
  fi
  printf 'xiaozhi_idf_build_summary idf=%s app_bin=%s app_size=%s bootloader_size=%s partition_size=%s assets_size=%s destructive=0 audio=0\n' \
    "$(idf.py --version 2>/dev/null | tr ' ' '_')" \
    "$app_bin" \
    "$(wc -c < "$app_bin" | tr -d ' ')" \
    "$(if [[ -f "$bootloader_bin" ]]; then wc -c < "$bootloader_bin" | tr -d ' '; else printf missing; fi)" \
    "$(if [[ -f "$partition_bin" ]]; then wc -c < "$partition_bin" | tr -d ' '; else printf missing; fi)" \
    "$(if [[ -f "$assets_bin" ]]; then wc -c < "$assets_bin" | tr -d ' '; else printf missing; fi)"
}

run_idf_build() {
  if [[ -f "$XIAOZHI_SOURCE_DIR/sdkconfig" ]] && grep -q '^CONFIG_IDF_TARGET="esp32s3"$' "$XIAOZHI_SOURCE_DIR/sdkconfig"; then
    (cd "$XIAOZHI_SOURCE_DIR" && idf.py -DSDKCONFIG_DEFAULTS="$XIAOZHI_SDKCONFIG_DEFAULTS" build)
    return
  fi
  (cd "$XIAOZHI_SOURCE_DIR" && idf.py -DSDKCONFIG_DEFAULTS="$XIAOZHI_SDKCONFIG_DEFAULTS" set-target esp32s3 build)
}

extract_merged_binary() {
  local zip_path extract_dir
  zip_path="$(download_firmware)"
  extract_dir="${zip_path%.zip}"
  mkdir -p "$extract_dir"
  unzip -o "$zip_path" merged-binary.bin -d "$extract_dir" >/dev/null
  printf '%s/merged-binary.bin\n' "$extract_dir"
}

run_esptool() {
  local esptool
  esptool="$(find_esptool)"
  "$esptool" --chip esp32s3 --port "$ARDUINO_PORT" --baud "$XIAOZHI_BAUD" "$@"
}

case "$ACTION" in
  latest)
    latest_asset_json | python3 -m json.tool
    ;;
  download)
    download_firmware
    ;;
  inspect)
    inspect_firmware
    ;;
  preflight)
    preflight
    ;;
  flash)
    require_yes "${2:-}"
    require_port
    run_esptool write_flash -z "$XIAOZHI_FLASH_ADDRESS" "$(extract_merged_binary)"
    ;;
  erase)
    require_yes "${2:-}"
    require_port
    run_esptool erase_flash
    ;;
  source-clone)
    if [[ -d "$XIAOZHI_SOURCE_DIR/.git" ]]; then
      git -C "$XIAOZHI_SOURCE_DIR" fetch --tags --prune
    else
      mkdir -p "$(dirname "$XIAOZHI_SOURCE_DIR")"
      git clone "$XIAOZHI_SOURCE_REPO" "$XIAOZHI_SOURCE_DIR"
    fi
    git -C "$XIAOZHI_SOURCE_DIR" describe --tags --always || git -C "$XIAOZHI_SOURCE_DIR" rev-parse --short HEAD
    ;;
  source-check)
    if [[ ! -d "$XIAOZHI_SOURCE_DIR/.git" ]]; then
      echo "Source not cloned. Run scripts/xiaozhi.sh source-clone first." >&2
      exit 1
    fi
    git -C "$XIAOZHI_SOURCE_DIR" status --short --branch
    rg -n "BOARD_TYPE_WAVESHARE_ESP32_S3_TOUCH_AMOLED_1_75C|esp32-s3-touch-amoled-1\\.75|Waveshare ESP32-S3-Touch-AMOLED-1\\.75C" \
      "$XIAOZHI_SOURCE_DIR/main/CMakeLists.txt" \
      "$XIAOZHI_SOURCE_DIR/main/Kconfig.projbuild" \
      "$XIAOZHI_SOURCE_DIR/main/boards/waveshare/esp32-s3-touch-amoled-1.75" \
      "$ROOT_DIR/config/xiaozhi-sdkconfig.defaults"
    ;;
  idf-env)
    idf_env_summary
    ;;
  idf-build)
    source_idf required
    prepare_idf_build_dir
    run_idf_build
    idf_build_summary
    ;;
  idf-flash)
    require_port
    source_idf required
    (cd "$XIAOZHI_SOURCE_DIR" && idf.py -p "$ARDUINO_PORT" flash)
    ;;
  idf-monitor)
    require_port
    source_idf required
    (cd "$XIAOZHI_SOURCE_DIR" && idf.py -p "$ARDUINO_PORT" monitor)
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
