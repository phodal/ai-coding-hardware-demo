#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
TMP_DIR="$(mktemp -d /tmp/waveshare-hook-smoke.XXXXXX)"
WORKTREE_ADDED=0
cleanup() {
  if [[ "$WORKTREE_ADDED" == "1" ]]; then
    git -C "$ROOT_DIR" worktree remove --force "$TMP_DIR" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

git -C "$ROOT_DIR" worktree add --detach "$TMP_DIR" HEAD >/dev/null
WORKTREE_ADDED=1

HEAD_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD)"
ZERO_SHA="0000000000000000000000000000000000000000"

NON_FEAT_SPEC="$TMP_DIR/non-feat-push-spec.txt"
FEAT_SPEC="$TMP_DIR/feat-push-spec.txt"
README_BEFORE="$TMP_DIR/README.before"

cp "$TMP_DIR/README.md" "$README_BEFORE"
printf 'refs/heads/master %s refs/heads/master %s\n' "$HEAD_SHA" "$HEAD_SHA" >"$NON_FEAT_SPEC"

(
  cd "$TMP_DIR"
  ./scripts/update-readme-for-feat-push.sh "$NON_FEAT_SPEC"
)

if ! cmp -s "$README_BEFORE" "$TMP_DIR/README.md"; then
  echo "hook_smoke_failed reason=non_feat_changed_readme" >&2
  exit 1
fi

printf 'refs/heads/feat/readme-hook %s refs/heads/feat/readme-hook %s\n' "$HEAD_SHA" "$ZERO_SHA" >"$FEAT_SPEC"

set +e
(
  cd "$TMP_DIR"
  ./scripts/update-readme-for-feat-push.sh "$FEAT_SPEC"
)
FEAT_RC=$?
set -e

if [[ "$FEAT_RC" != "2" ]]; then
  echo "hook_smoke_failed reason=feat_exit_code expected=2 actual=$FEAT_RC" >&2
  exit 1
fi

if cmp -s "$README_BEFORE" "$TMP_DIR/README.md"; then
  echo "hook_smoke_failed reason=feat_did_not_update_readme" >&2
  exit 1
fi

if ! grep -Fq '<!-- feat-push-readme:start -->' "$TMP_DIR/README.md"; then
  echo "hook_smoke_failed reason=missing_start_marker" >&2
  exit 1
fi

if ! grep -Fq 'refs/heads/feat/readme-hook -> refs/heads/feat/readme-hook' "$TMP_DIR/README.md"; then
  echo "hook_smoke_failed reason=missing_feat_ref" >&2
  exit 1
fi

echo "hook_smoke_summary non_feat=0 feat=2 readme_updated=1"
