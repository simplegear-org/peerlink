#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: tool/release_commit_message.sh <version> [release_type]" >&2
  exit 64
fi

VERSION="$1"
RELEASE_TYPE="${2:-release}"

echo "chore(release): ${RELEASE_TYPE} app version ${VERSION}"
