#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

XIAOZHI_READINESS_BACKUP="${XIAOZHI_READINESS_BACKUP:-0}"
XIAOZHI_READINESS_BUILD="${XIAOZHI_READINESS_BUILD:-1}"
XIAOZHI_READINESS_BACKUP_DIR="${XIAOZHI_READINESS_BACKUP_DIR:-$ROOT_DIR/.vendor/xiaozhi/backups}"

latest_backup() {
  find "$XIAOZHI_READINESS_BACKUP_DIR" -maxdepth 1 -type f -name 'esp32s3-flash-*.bin' -print 2>/dev/null | sort | tail -1
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

echo "xiaozhi_readiness_start destructive=0 audio=0 backup_mode=$XIAOZHI_READINESS_BACKUP build=$XIAOZHI_READINESS_BUILD"

"$ROOT_DIR/scripts/xiaozhi.sh" preflight
"$ROOT_DIR/scripts/xiaozhi.sh" source-check
"$ROOT_DIR/scripts/xiaozhi.sh" idf-env

if [[ "$XIAOZHI_READINESS_BUILD" == "1" ]]; then
  "$ROOT_DIR/scripts/xiaozhi.sh" idf-build
else
  echo "xiaozhi_readiness_idf_build status=skipped reason=XIAOZHI_READINESS_BUILD_not_1 destructive=0 audio=0"
fi

if [[ "$XIAOZHI_READINESS_BACKUP" == "1" ]]; then
  "$ROOT_DIR/scripts/xiaozhi.sh" backup
else
  backup="$(latest_backup)"
  if [[ -z "$backup" ]]; then
    echo "xiaozhi_readiness_backup status=missing action=run_XIAOZHI_READINESS_BACKUP_1 destructive=0 audio=0" >&2
    exit 1
  fi
  printf 'xiaozhi_readiness_backup status=existing path=%s bytes=%s sha256=%s destructive=0 audio=0\n' \
    "$backup" "$(stat -f %z "$backup")" "$(sha256_file "$backup")"
fi

echo "xiaozhi_readiness_summary status=ok backup_mode=$XIAOZHI_READINESS_BACKUP build=$XIAOZHI_READINESS_BUILD destructive=0 audio=0"
