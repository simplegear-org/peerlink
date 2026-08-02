#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: tool/generate_release_changelog_body.sh <version> [--lang en|ru]" >&2
  exit 64
fi

VERSION="$1"
LANGUAGE="en"
if [[ $# -ge 3 ]]; then
  if [[ "$2" != "--lang" ]]; then
    echo "Usage: tool/generate_release_changelog_body.sh <version> [--lang en|ru]" >&2
    exit 64
  fi
  LANGUAGE="$3"
elif [[ $# -eq 2 ]]; then
  if [[ "$2" != "en" && "$2" != "ru" ]]; then
    echo "Usage: tool/generate_release_changelog_body.sh <version> [--lang en|ru]" >&2
    exit 64
  fi
  LANGUAGE="$2"
fi

RELEASE_COMMIT_PATTERN='^chore\(release\):'

find_previous_release_commit() {
  local commits
  commits="$(git log --grep="$RELEASE_COMMIT_PATTERN" --format='%H' -n 5 2>/dev/null || true)"
  if [[ -z "${commits//[[:space:]]/}" ]]; then
    return 0
  fi
  if git log -1 --format='%s' | grep -Eq "$RELEASE_COMMIT_PATTERN"; then
    printf '%s\n' "$commits" | sed -n '2p'
    return 0
  fi
  printf '%s\n' "$commits" | sed -n '1p'
}

normalize_subject() {
  local subject="$1"
  subject="${subject#\[patch\] }"
  subject="${subject#\[minor\] }"
  subject="${subject#\[major\] }"
  subject="${subject#\[build\] }"
  subject="${subject#\#patch }"
  subject="${subject#\#minor }"
  subject="${subject#\#major }"
  subject="${subject#\#build }"
  printf '%s' "$subject"
}

append_bullet() {
  local array_name="$1"
  local value="$2"
  eval "$array_name+=(\"\$value\")"
}

previous_release_commit="$(find_previous_release_commit)"
LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT
if [[ -n "${previous_release_commit:-}" ]]; then
  git log "${previous_release_commit}..HEAD" --format='%s' --reverse > "$LOG_FILE"
else
  git log --format='%s' --reverse -n 40 > "$LOG_FILE"
fi

added=()
changed=()
fixed=()

if [[ "$LANGUAGE" == "ru" ]]; then
  added_heading="### Добавлено"
  changed_heading="### Изменено"
  fixed_heading="### Исправлено"
  default_line="- Подготовлен автоматический черновик changelog для ${VERSION}."
else
  added_heading="### Added"
  changed_heading="### Changed"
  fixed_heading="### Fixed"
  default_line="- Automatic changelog draft prepared for ${VERSION}."
fi

while IFS= read -r subject || [[ -n "$subject" ]]; do
  if [[ -z "${subject//[[:space:]]/}" ]]; then
    continue
  fi
  if [[ "$subject" =~ $RELEASE_COMMIT_PATTERN ]]; then
    continue
  fi
  lower="$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]')"
  subject="$(normalize_subject "$subject")"
  subject="${subject#"Merge pull request "}"
  subject="${subject#"Merge branch "}"
  if [[ -z "${subject//[[:space:]]/}" ]]; then
    continue
  fi

  case "$lower" in
    feat:*|feature:*|add:*|added:* )
      append_bullet added "$subject"
      ;;
    fix:*|bugfix:*|hotfix:*|correct*|resolve*|repair* )
      append_bullet fixed "$subject"
      ;;
    perf:*|refactor:*|chore:*|docs:*|style:*|test:* )
      append_bullet changed "$subject"
      ;;
    * )
      append_bullet changed "$subject"
      ;;
  esac
done < "$LOG_FILE"

if [[ ${#added[@]} -eq 0 && ${#changed[@]} -eq 0 && ${#fixed[@]} -eq 0 ]]; then
  cat <<EOF
${changed_heading}

${default_line}
EOF
  exit 0
fi

if [[ ${#added[@]} -gt 0 ]]; then
  printf '%s\n\n' "$added_heading"
  printf -- '- %s\n' "${added[@]}"
  printf '\n'
fi
if [[ ${#changed[@]} -gt 0 ]]; then
  printf '%s\n\n' "$changed_heading"
  printf -- '- %s\n' "${changed[@]}"
  printf '\n'
fi
if [[ ${#fixed[@]} -gt 0 ]]; then
  printf '%s\n\n' "$fixed_heading"
  printf -- '- %s\n' "${fixed[@]}"
  printf '\n'
fi
