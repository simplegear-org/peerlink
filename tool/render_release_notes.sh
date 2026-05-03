#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: tool/render_release_notes.sh <version> [--lang en|ru]" >&2
  exit 64
fi

VERSION="$1"
LANGUAGE="en"
if [[ $# -ge 3 ]]; then
  if [[ "$2" != "--lang" ]]; then
    echo "Usage: tool/render_release_notes.sh <version> [--lang en|ru]" >&2
    exit 64
  fi
  LANGUAGE="$3"
elif [[ $# -eq 2 ]]; then
  if [[ "$2" != "en" && "$2" != "ru" ]]; then
    echo "Usage: tool/render_release_notes.sh <version> [--lang en|ru]" >&2
    exit 64
  fi
  LANGUAGE="$2"
fi

case "$LANGUAGE" in
  en)
    CHANGELOG_FILE="CHANGELOG.md"
    TEMPLATE_FILE=".github/release-template.md"
    ;;
  ru)
    CHANGELOG_FILE="CHANGELOG_RU.md"
    TEMPLATE_FILE=".github/release-template-ru.md"
    ;;
  *)
    echo "Unsupported language: $LANGUAGE" >&2
    exit 64
    ;;
esac

if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "CHANGELOG.md not found" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo ".github/release-template.md not found" >&2
  exit 1
fi

extract_section() {
  local header="## [${VERSION}]"
  awk -v header="$header" '
    index($0, header) == 1 { capture=1; next }
    capture && index($0, "## [") == 1 { exit }
    capture { print }
  ' "$CHANGELOG_FILE"
}

extract_previous_version() {
  local header="## [${VERSION}]"
  awk -v header="$header" '
    index($0, header) == 1 { current_found=1; next }
    current_found && match($0, /^## \[([^]]+)\]/, m) {
      print m[1]
      exit
    }
  ' "$CHANGELOG_FILE"
}

section_is_placeholder() {
  local body="$1"
  local compact
  compact="$(printf '%s\n' "$body" | tr -d '[:space:]')"
  if [[ -z "$compact" ]]; then
    return 0
  fi
  if printf '%s\n' "$body" | grep -Eq '^[[:space:]]*-[[:space:]]*TODO([[:space:]]|$)'; then
    return 0
  fi
  if printf '%s\n' "$body" | grep -Eq '^[[:space:]]*TODO([[:space:]]|$)'; then
    return 0
  fi
  if printf '%s\n' "$body" | grep -Eq '^[[:space:]]*-[[:space:]]*НО[[:space:]]*ДО([[:space:]]|$)'; then
    return 0
  fi
  return 1
}

BODY="$(extract_section)"
SOURCE="CHANGELOG"

if section_is_placeholder "$BODY"; then
  chmod +x tool/generate_release_changelog_body.sh
  BODY="$(tool/generate_release_changelog_body.sh "$VERSION" --lang "$LANGUAGE")"
  SOURCE="git-history"
fi

BODY="$(printf '%s\n' "$BODY" | sed '${/^$/d;}')"

TEMP_BODY="$(mktemp)"
trap 'rm -f "$TEMP_BODY"' EXIT
printf '%s\n' "$BODY" > "$TEMP_BODY"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "release_notes_source=${SOURCE}"
    echo "release_notes_lang=${LANGUAGE}"
    local_previous_version="$(extract_previous_version || true)"
    if [[ -n "${local_previous_version:-}" ]]; then
      echo "previous_version=${local_previous_version}"
    fi
  } >> "$GITHUB_OUTPUT"
fi

sed \
  -e "s/{{VERSION}}/${VERSION}/g" \
  -e "/{{CHANGELOG_BODY}}/{
r $TEMP_BODY
d
}" \
  "$TEMPLATE_FILE"
