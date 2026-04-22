#!/usr/bin/env bash
set -euo pipefail

MESSAGE="${1:-}"
LOWER="$(printf '%s' "$MESSAGE" | tr '[:upper:]' '[:lower:]')"

if [[ "$MESSAGE" == *"BREAKING CHANGE"* ]] || [[ "$LOWER" == *"[major]"* ]] || [[ "$LOWER" == *"#major"* ]]; then
  echo "major"
elif [[ "$LOWER" == *"[minor]"* ]] || [[ "$LOWER" == *"#minor"* ]] || [[ "$LOWER" == feat:* ]]; then
  echo "minor"
elif [[ "$LOWER" == *"[build]"* ]] || [[ "$LOWER" == *"#build"* ]] || [[ "$LOWER" == build:* ]]; then
  echo "build"
else
  echo "patch"
fi
