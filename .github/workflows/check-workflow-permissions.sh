#!/usr/bin/env bash
# Fails unless every workflow in the directory declares its token scopes and
# those scopes are exactly the ones the expected list names. A workflow with
# no permissions: key runs with the repository default, and a dropped scope
# would otherwise surface only on that workflow's next run, which for a
# release or dispatch workflow can be months away (#148). A workflow is
# covered by a top-level block, or with none by a block on every job. Only a
# block mapping or {} is accepted, so write-all, read-all and flow mappings
# fail here.
#
# The expected list holds one line per scope, <workflow> <where> <scope>,
# where <where> is workflow or job:<id> and <scope> is name:level or {}.
#
# Usage: check-workflow-permissions.sh <expected list> <workflow directory>
set -uo pipefail

if [ "$#" != 2 ]; then
  echo "usage: check-workflow-permissions.sh <expected list> <workflow directory>" >&2
  exit 2
fi
EXPECTED="$1"
DIR="$2"
if [ ! -f "$EXPECTED" ]; then
  echo "::error::no expected list at $EXPECTED"
  exit 1
fi
mapfile -t FILES < <(find "$DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)
if [ "${#FILES[@]}" = 0 ]; then
  echo "::error::no workflow files in $DIR"
  exit 1
fi

FAILED=0
ACTUAL="$(mktemp)"
trap 'rm -f "$ACTUAL"' EXIT

for FILE in "${FILES[@]}"; do
  # Job ids are read at two spaces under jobs:, and job-level keys at four.
  # Deeper text, a run: script included, is never read as a key.
  # Carriage returns are stripped so a CRLF checkout reads the same as CI's LF.
  awk -v file="$FILE" -v name="${FILE##*/}" '
    function err(msg) { printf "::error file=%s,line=%d::%s\n", file, NR, msg | "cat 1>&2"; bad = 1 }
    function close_block() { if (open && !count) err("empty permissions: block for " where); open = 0 }
    function start(w, rest) {
      if (w in declared) { err("second permissions: key for " w); return }
      declared[w] = 1
      sub(/^[[:space:]]*/, "", rest); sub(/[[:space:]]*(#.*)?$/, "", rest)
      if (rest == "{}") { print name, w, "{}"; return }
      if (rest != "") { err("permissions: for " w " is not a block mapping or {}: " rest); return }
      open = 1; count = 0; where = w; depth = (w == "workflow") ? 0 : 4
    }
    { sub(/\r$/, "") }
    /^[[:space:]]*(#|$)/ { next }
    {
      match($0, /^ */); indent = RLENGTH
      if (open && indent <= depth) close_block()
    }
    open {
      line = $0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]*(#.*)?$/, "", line)
      if (line !~ /^[a-z-]+:[[:space:]]*(read|write|none)$/) { err("not a name: level scope for " where ": " line); next }
      split(line, kv, /:[[:space:]]*/)
      if ((where SUBSEP kv[1]) in scoped) { err("scope " kv[1] " twice for " where); next }
      scoped[where, kv[1]] = 1; count++
      print name, where, kv[1] ":" kv[2]; next
    }
    indent == 0 { top = $0; sub(/:.*/, "", top) }
    /^permissions:/ { start("workflow", substr($0, 13)); next }
    top == "jobs" && /^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$/ {
      job = $0; sub(/^  /, "", job); sub(/:.*/, "", job); jobs[++njobs] = job; jobline[njobs] = NR; next
    }
    top == "jobs" && njobs && /^    permissions:/ { start("job:" job, substr($0, 17)); next }
    END {
      close_block()
      if (!("workflow" in declared)) {
        if (!njobs) err("no top-level permissions: block and no job found under jobs:")
        for (i = 1; i <= njobs; i++)
          if (!(("job:" jobs[i]) in declared)) { NR = jobline[i]; err("job " jobs[i] " has no permissions: block and the workflow has none") }
      }
      exit bad
    }
  ' "$FILE" >> "$ACTUAL" || FAILED=1
done

DIFF="$(diff <(grep -v '^[[:space:]]*\(#\|$\)' "$EXPECTED" | tr -d '\r' | LC_ALL=C sort) <(LC_ALL=C sort "$ACTUAL"))"
if [ -n "$DIFF" ]; then
  while IFS= read -r LINE; do
    case "$LINE" in
      "< "*) echo "::error::expected but not declared: ${LINE#< }" ;;
      "> "*) echo "::error::declared but not expected: ${LINE#> }" ;;
    esac
  done <<< "$DIFF"
  FAILED=1
fi

if [ "$FAILED" = 0 ]; then
  echo "${#FILES[@]} workflow(s) declare exactly the expected permissions"
fi
exit "$FAILED"
