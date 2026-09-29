#!/usr/bin/env bash
# Fails unless the given workflow declares one top-level permissions: block
# holding exactly issues: write, and no permissions: key anywhere else. The
# support job only comments on, closes and reopens issues, and a job-level
# permissions: would replace the top-level one, so either a missing block or
# a second one hands the token scopes it never uses (#87). The block form is
# the only one accepted, so write-all or a flow mapping fails here.
#
# Usage: check-support-permissions.sh <workflow file>
set -uo pipefail

if [ "$#" != 1 ]; then
  echo "usage: check-support-permissions.sh <workflow file>" >&2
  exit 2
fi
FILE="$1"
if [ ! -f "$FILE" ]; then
  echo "::error::no workflow file at $FILE"
  exit 1
fi

# Carriage returns are stripped so a CRLF checkout reads the same as CI's LF.
awk -v file="$FILE" '
  function err(msg) { printf "::error file=%s,line=%d::%s\n", file, NR, msg; bad = 1 }
  { sub(/\r$/, "") }
  /^[[:space:]]*(#|$)/ { next }
  /^[^[:space:]]/ { inblock = 0 }
  /^permissions:/ {
    if (seen++) { err("second top-level permissions: key"); next }
    if ($0 !~ /^permissions:[[:space:]]*(#.*)?$/) { err("permissions: is not a block mapping"); next }
    inblock = 1; next
  }
  /^[[:space:]]+permissions:/ { err("permissions: below the top level overrides the workflow scope"); next }
  inblock {
    line = $0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]*(#.*)?$/, "", line)
    if (line == "issues: write") issues++
    else err("scope other than issues: write: " line)
  }
  END {
    if (!seen) { printf "::error file=%s::no top-level permissions: block\n", file; exit 1 }
    if (issues != 1) { printf "::error file=%s::permissions: must hold issues: write exactly once\n", file; exit 1 }
    if (bad) exit 1
    printf "%s: permissions: is issues: write only\n", file
  }
' "$FILE"
