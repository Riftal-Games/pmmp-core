#!/usr/bin/env bash
# Fails if any run: script in the given workflow files contains a ${{ }}
# expression. The runner pastes an expression's value into the script text
# before the shell sees it, so a release tag or dispatch input holding shell
# syntax would run as shell (#119). Values reach a script through env: and
# are read as shell variables. A shell comment inside a script is still
# script text to the runner, so it is checked too. Each file must hold at
# least one run: key, so a check that stopped finding them fails here.
#
# Usage: check-run-expressions.sh <workflow file>...
set -uo pipefail

if [ "$#" = 0 ]; then
  echo "usage: check-run-expressions.sh <workflow file>..." >&2
  exit 2
fi

FAILED=0
for FILE in "$@"; do
  if [ ! -f "$FILE" ]; then
    echo "::error::no workflow file at $FILE"
    FAILED=1
    continue
  fi
  awk -v file="$FILE" '
    function indent(s) { match(s, /^ */); return RLENGTH }
    function flag(n) {
      printf "::error file=%s,line=%d::run: script interpolates a ${{ }} expression; pass it through env: instead\n", file, n
      bad = 1
    }
    {
      ind = indent($0)
      body = substr($0, ind + 1)
    }
    inblock && body != "" && ind <= runind { inblock = 0 }
    inblock { if (index($0, "${{")) flag(NR); next }
    body ~ /^#/ { next }
    body ~ /^(- +)?run:/ {
      seen++
      runind = ind
      value = body
      sub(/^(- +)?run:[[:space:]]*/, "", value)
      if (value ~ /^[|>]/) { inblock = 1; next }
      if (index(value, "${{")) flag(NR)
    }
    END {
      if (seen == 0) {
        printf "::error file=%s::no run: key found, so nothing was checked\n", file
        exit 1
      }
      printf "%s: %d run: script(s) checked\n", file, seen
      exit bad
    }
  ' "$FILE" || FAILED=1
done
exit "$FAILED"
