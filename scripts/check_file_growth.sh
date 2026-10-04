#!/usr/bin/env bash
# Advisory: names source files over the threshold that this branch makes longer. Always exits 0;
# length alone is fine, unexamined growth is not.

set -euo pipefail
cd "$(dirname "$0")/.."

THRESHOLD=800

base=$(git merge-base refs/remotes/origin/main HEAD 2>/dev/null || git rev-parse HEAD)

changed=$( (git diff --name-only "$base" 2>/dev/null; git diff --name-only; git diff --name-only --cached; git ls-files --others --exclude-standard) | sort -u )

flagged=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    lib/*.ex) ;;
    assets/js/*.ts|assets/js/*.js) ;;
    *) continue ;;
  esac
  case "$f" in
    *test*|assets/vendor/*) continue ;;
  esac
  [ -f "$f" ] || continue

  new_lines=$(wc -l < "$f" | tr -d ' ')
  if git cat-file -e "$base:$f" 2>/dev/null; then
    old_lines=$(git show "$base:$f" | wc -l | tr -d ' ')
  else
    old_lines=0
  fi

  if [ "$new_lines" -ge "$THRESHOLD" ] && [ "$new_lines" -gt "$old_lines" ]; then
    if [ "$flagged" -eq 0 ]; then
      echo ""
      echo "file-growth check (advisory): this branch grows files already over ${THRESHOLD} lines."
      echo "  Before committing, ask whether the addition belongs in a module of its own."
      echo ""
    fi
    flagged=1
    printf "  %-60s %5s -> %5s  (+%s)\n" "$f" "$old_lines" "$new_lines" "$((new_lines - old_lines))"
  fi
done <<< "$changed"

if [ "$flagged" -eq 1 ]; then
  echo ""
fi

exit 0
