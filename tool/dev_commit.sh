#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: tool/dev_commit.sh [--bump-build] <commit message>" >&2
  exit 64
fi

SHOULD_BUMP_BUILD=false
if [[ "${1:-}" == "--bump-build" ]]; then
  SHOULD_BUMP_BUILD=true
  shift
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: tool/dev_commit.sh [--bump-build] <commit message>" >&2
  exit 64
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "dev" ]]; then
  echo "tool/dev_commit.sh is intended for the dev branch. Current branch: ${BRANCH}" >&2
  exit 65
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Current directory is not a git repository" >&2
  exit 66
fi

MESSAGE="$*"
VERSION_SUFFIX=""
RELEASE_TYPE=""
if [[ "$MESSAGE" =~ \[(major|minor|patch|build)\] ]]; then
  RELEASE_TYPE="${BASH_REMATCH[1]}"
fi

if [[ -n "$RELEASE_TYPE" && "$SHOULD_BUMP_BUILD" == "true" ]]; then
  echo "Do not combine [patch]/[minor]/[major]/[build] markers with --bump-build" >&2
  exit 68
fi

if [[ -n "$RELEASE_TYPE" ]]; then
  VERSION="$(tool/prepare_release.sh "$RELEASE_TYPE")"
  VERSION_SUFFIX=" with version ${VERSION}"
elif [[ "$SHOULD_BUMP_BUILD" == "true" ]]; then
  VERSION="$(dart run tool/bump_version.dart build)"
  VERSION_SUFFIX=" with version ${VERSION}"
fi

git add -A

if git diff --cached --quiet; then
  if [[ "$SHOULD_BUMP_BUILD" == "true" ]]; then
    echo "Nothing to commit after optional build bump (${VERSION})" >&2
  else
    echo "Nothing to commit" >&2
  fi
  exit 67
fi

git commit -m "${MESSAGE}"

echo "Committed dev changes${VERSION_SUFFIX}"
