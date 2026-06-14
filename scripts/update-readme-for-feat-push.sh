#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
README_FILE="$ROOT_DIR/README.md"
PUSH_SPEC_FILE="${1:-/dev/stdin}"
ZERO_SHA="0000000000000000000000000000000000000000"

if [[ ! -f "$README_FILE" ]]; then
  echo "README.md not found; cannot update feature push notes." >&2
  exit 1
fi

FEAT_COMMITS_FILE="$(mktemp)"
FEAT_REFS_FILE="$(mktemp)"
BLOCK_FILE="$(mktemp)"
NEXT_README_FILE="$(mktemp)"
trap 'rm -f "$FEAT_COMMITS_FILE" "$FEAT_REFS_FILE" "$BLOCK_FILE" "$NEXT_README_FILE"' EXIT

ref_has_feat() {
  printf '%s\n' "$1" | grep -Eiq '(^|[/_.-])feat([/_.-]|$)'
}

subject_has_feat() {
  printf '%s\n' "$1" | grep -Eiq '^feat(\([^)]+\))?!?:|(^|[[:space:]])feat([[:space:]:_.-]|$)'
}

escape_markdown_cell() {
  sed 's/\\/\\\\/g; s/|/\\|/g'
}

append_commit_if_feat() {
  local sha short subject safe_subject
  sha="$1"
  subject="$(git log -1 --format=%s "$sha")"

  if subject_has_feat "$subject"; then
    short="$(git rev-parse --short "$sha")"
    safe_subject="$(printf '%s' "$subject" | escape_markdown_cell)"
    printf '%s\t%s\n' "$short" "$safe_subject" >>"$FEAT_COMMITS_FILE"
  fi
}

while read -r local_ref local_sha remote_ref remote_sha; do
  [[ -n "${local_ref:-}" ]] || continue
  [[ "$local_sha" == "$ZERO_SHA" ]] && continue

  if ref_has_feat "$local_ref" || ref_has_feat "$remote_ref"; then
    printf '%s -> %s\n' "$local_ref" "$remote_ref" >>"$FEAT_REFS_FILE"
  fi

  if [[ "$remote_sha" == "$ZERO_SHA" ]]; then
    while read -r sha; do
      [[ -n "$sha" ]] && append_commit_if_feat "$sha"
    done < <(git rev-list --reverse "$local_sha" --not --remotes)
  else
    while read -r sha; do
      [[ -n "$sha" ]] && append_commit_if_feat "$sha"
    done < <(git rev-list --reverse "$remote_sha..$local_sha")
  fi
done <"$PUSH_SPEC_FILE"

if [[ ! -s "$FEAT_COMMITS_FILE" && ! -s "$FEAT_REFS_FILE" ]]; then
  exit 0
fi

{
  printf '<!-- feat-push-readme:start -->\n'
  printf '## Feature Push Notes\n\n'
  printf 'This section is maintained by `.githooks/pre-push` when outgoing push refs or commit subjects include `feat`.\n\n'

  if [[ -s "$FEAT_REFS_FILE" ]]; then
    printf 'Triggered push refs:\n\n'
    printf '| Ref |\n'
    printf '| --- |\n'
    sort -u "$FEAT_REFS_FILE" | while read -r ref_line; do
      safe_ref="$(printf '%s' "$ref_line" | escape_markdown_cell)"
      printf '| `%s` |\n' "$safe_ref"
    done
    printf '\n'
  fi

  if [[ -s "$FEAT_COMMITS_FILE" ]]; then
    printf 'Outgoing feature commits:\n\n'
    printf '| Commit | Subject |\n'
    printf '| --- | --- |\n'
    sort -u "$FEAT_COMMITS_FILE" | while IFS=$'\t' read -r short subject; do
      printf '| `%s` | %s |\n' "$short" "$subject"
    done
    printf '\n'
  fi

  printf 'Commit this README update, then run `git push` again.\n'
  printf '<!-- feat-push-readme:end -->\n'
} >"$BLOCK_FILE"

if grep -Fq '<!-- feat-push-readme:start -->' "$README_FILE"; then
  awk -v block_file="$BLOCK_FILE" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block = block line ORS
      }
    }
    /<!-- feat-push-readme:start -->/ {
      printf "%s", block
      in_block = 1
      next
    }
    /<!-- feat-push-readme:end -->/ {
      in_block = 0
      next
    }
    !in_block { print }
  ' "$README_FILE" >"$NEXT_README_FILE"
else
  cp "$README_FILE" "$NEXT_README_FILE"
  {
    printf '\n'
    cat "$BLOCK_FILE"
  } >>"$NEXT_README_FILE"
fi

if cmp -s "$README_FILE" "$NEXT_README_FILE"; then
  exit 0
fi

mv "$NEXT_README_FILE" "$README_FILE"
echo "README.md was updated for outgoing feat push metadata." >&2
echo "Review and commit README.md, then run git push again." >&2
exit 2
