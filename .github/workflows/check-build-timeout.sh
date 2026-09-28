#!/usr/bin/env bash
# Fails unless every docker/build-push-action step in the given workflow files
# sets timeout-minutes as a step key with a positive whole number. A hung
# build otherwise holds the runner for the job's 360-minute default (#79), and
# a timeout-minutes indented under with: is only an unknown action input, so
# nothing else would notice it doing nothing. Each file must hold at least one
# such step, so a renamed action fails here rather than passing unchecked.
#
# Usage: check-build-timeout.sh <workflow file>...
set -uo pipefail

if [ "$#" = 0 ]; then
  echo "usage: check-build-timeout.sh <workflow file>..." >&2
  exit 2
fi

FAILED=0
for FILE in "$@"; do
  if [ ! -f "$FILE" ]; then
    echo "::error::no workflow file at $FILE"
    FAILED=1
    continue
  fi
  awk -v file="$FILE" -v q="'" '
    function indent(s) { match(s, /^ */); return RLENGTH }
    function close_step() {
      if (build) {
        seen++
        if (!timeout) {
          printf "::error file=%s,line=%d::docker/build-push-action step has no step-level timeout-minutes\n", file, start
          bad = 1
        }
      }
      build = 0; timeout = 0; instep = 0
    }
    /^[[:space:]]*(#|$)/ { next }
    {
      ind = indent($0)
      body = substr($0, ind + 1)
    }
    insteps && (ind < dash || (ind == dash && body !~ /^- /)) {
      close_step(); insteps = 0; dash = -1
    }
    insteps && ind == dash && body ~ /^- / {
      close_step(); instep = 1; start = NR
      body = substr(body, 3); sub(/^ +/, "", body); ind = dash + 2
    }
    body ~ /^steps:[[:space:]]*$/ { insteps = 1; dash = -1; stepsind = ind; next }
    insteps && dash < 0 && body ~ /^- / && ind >= stepsind {
      dash = ind; instep = 1; start = NR
      body = substr(body, 3); sub(/^ +/, "", body); ind = dash + 2
    }
    instep && ind == dash + 2 {
      if (body ~ ("^uses:[[:space:]]*[\"" q "]?docker/build-push-action@")) build = 1
      if (body ~ /^timeout-minutes:[[:space:]]*[1-9][0-9]*[[:space:]]*$/) timeout = 1
    }
    END {
      close_step()
      if (seen == 0) {
        printf "::error file=%s::no docker/build-push-action step found, so nothing was checked\n", file
        exit 1
      }
      printf "%s: %d build step(s) checked\n", file, seen
      exit bad
    }
  ' "$FILE" || FAILED=1
done
exit "$FAILED"
