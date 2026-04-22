#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: tool/mirror_subset.sh <target-branch>" >&2
  exit 64
fi

TARGET_BRANCH="$1"

if [[ -z "${MIRROR_REPO_TOKEN:-}" ]]; then
  echo "MIRROR_REPO_TOKEN is empty, skipping mirror step"
  exit 0
fi

if [[ -z "${MIRROR_TARGET_REPO:-}" ]]; then
  echo "MIRROR_TARGET_REPO is empty" >&2
  exit 1
fi

if [[ -z "${MIRROR_INCLUDE:-}" ]]; then
  echo "MIRROR_INCLUDE is empty" >&2
  exit 1
fi

SRC_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
TMP_DIR="$(mktemp -d)"
TARGET_DIR="$TMP_DIR/target"

trap 'rm -rf "$TMP_DIR"' EXIT

git clone "https://x-access-token:${MIRROR_REPO_TOKEN}@github.com/${MIRROR_TARGET_REPO}.git" "$TARGET_DIR"
cd "$TARGET_DIR"

git checkout --orphan mirror-sync
git rm -rf . >/dev/null 2>&1 || true
find . -mindepth 1 -maxdepth 1 ! -name ".git" -exec rm -rf {} +

while IFS= read -r path; do
  path="$(printf "%s" "$path" | tr -d '\r')"
  path="${path#"${path%%[![:space:]]*}"}"
  path="${path%"${path##*[![:space:]]}"}"
  path="${path#./}"
  path="${path#/}"
  [[ -z "$path" ]] && continue
  [[ "$path" =~ ^[[:space:]]*# ]] && continue

  if [[ -e "$SRC_DIR/$path" ]]; then
    mkdir -p "$TARGET_DIR/$(dirname "$path")"
    rsync -a "$SRC_DIR/$path" "$TARGET_DIR/$(dirname "$path")/"
  else
    echo "warn: source path not found, skip: $path"
  fi
done < <(printf "%s\n" "$MIRROR_INCLUDE")

git add -A
if git diff --cached --quiet; then
  echo "No files to mirror after filtering"
  exit 0
fi

git -c user.name="github-actions[bot]" -c user.email="github-actions[bot]@users.noreply.github.com" \
  commit -m "chore: mirror subset from ${GITHUB_REPOSITORY:-local}@${GITHUB_SHA:-local}"

git push --force origin mirror-sync:"${TARGET_BRANCH}"
