#!/usr/bin/env bash
# Fails unless every POCKETMINE_ARGS assignment in the given workflow files
# passes --auto-report.enabled=0 exactly once and no other auto-report value.
# The server reads the flag through getopt and casts it with (bool), so a
# missing flag leaves the shipped enabled: true in force, "=false" casts to
# true, and a repeated flag arrives as an array that also casts to true (#91).
# Each file must hold at least one assignment, so a renamed variable fails
# here rather than passing with nothing checked.
#
# Usage: check-auto-report-flag.sh <workflow file>...
set -uo pipefail

if [ "$#" = 0 ]; then
  echo "usage: check-auto-report-flag.sh <workflow file>..." >&2
  exit 2
fi

FAILED=0
for FILE in "$@"; do
  if [ ! -f "$FILE" ]; then
    echo "::error::no workflow file at $FILE"
    FAILED=1
    continue
  fi
  SEEN=0
  while IFS= read -r ENTRY; do
    NUM="${ENTRY%%:*}"
    LINE="${ENTRY#*:}"
    if [[ "$LINE" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    SEEN=$((SEEN + 1))
    COUNT="$(grep -oF -- "--auto-report.enabled" <<< "$LINE" | wc -l)"
    if [ "$COUNT" != 1 ] || ! grep -qE -- '--auto-report\.enabled=0([" ]|$)' <<< "$LINE"; then
      echo "::error file=$FILE,line=$NUM::POCKETMINE_ARGS must pass --auto-report.enabled=0 exactly once, found $COUNT auto-report flag(s)"
      FAILED=1
    fi
  done < <(grep -nE 'POCKETMINE_ARGS[=:]' "$FILE")
  if [ "$SEEN" = 0 ]; then
    echo "::error file=$FILE::no POCKETMINE_ARGS assignment found, so nothing was checked"
    FAILED=1
  else
    echo "$FILE: $SEEN POCKETMINE_ARGS line(s) checked"
  fi
done
exit "$FAILED"
