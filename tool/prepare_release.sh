#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: tool/prepare_release.sh <patch|minor|major|build|x.y.z+n> [YYYY-MM-DD]" >&2
  exit 64
fi

INPUT="$1"
RELEASE_DATE="${2:-$(date +%F)}"

if [[ "$INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  VERSION="$(dart run tool/bump_version.dart set "$INPUT")"
else
  VERSION="$(dart run tool/bump_version.dart "$INPUT")"
fi

chmod +x tool/generate_release_changelog_body.sh
EN_BODY="$(tool/generate_release_changelog_body.sh "$VERSION" --lang en)"
RU_BODY="$(tool/generate_release_changelog_body.sh "$VERSION" --lang ru)"

EN_TEMPLATE="$(mktemp)"
RU_TEMPLATE="$(mktemp)"

cat > "$EN_TEMPLATE" <<EOF
## [$VERSION] - $RELEASE_DATE

${EN_BODY}

EOF

cat > "$RU_TEMPLATE" <<EOF
## [$VERSION] - $RELEASE_DATE

${RU_BODY}

EOF

trap 'rm -f "$EN_TEMPLATE" "$RU_TEMPLATE"' EXIT

insert_entry_if_missing() {
  local file="$1"
  local template="$2"
  local temp_file
  temp_file="$(mktemp)"

  if grep -Fq "## [$VERSION] - $RELEASE_DATE" "$file"; then
    return 0
  fi

  {
    head -n 4 "$file"
    printf '\n'
    cat "$template"
    tail -n +5 "$file"
  } > "$temp_file"

  mv "$temp_file" "$file"
}

insert_entry_if_missing "CHANGELOG.md" "$EN_TEMPLATE"
insert_entry_if_missing "CHANGELOG_RU.md" "$RU_TEMPLATE"

echo "$VERSION"
