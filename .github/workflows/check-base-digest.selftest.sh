#!/usr/bin/env bash
# Self-test for check-base-digest.sh. Every case sets RESOLVE_CMD to a stub,
# so the weekly drift check is proven offline: a match passes, a moved tag
# fails and reports both digests, and a lookup that fails or returns junk
# fails as an error rather than passing.
set -uo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/check-base-digest.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0
RAN=0
EXPECTED_CASES=8

A=sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac
B=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

dockerfile() {
  local file="$DIR/$1.Dockerfile"
  printf 'FROM ubuntu:24.04@%s AS build-php\nFROM ubuntu:24.04@%s AS build-pocketmine\nFROM ubuntu:24.04@%s\n' "$2" "$3" "$4" > "$file"
  echo "$file"
}

# expect <name> <exit> <dockerfile> <resolver> <pattern in output> [<pattern in GITHUB_OUTPUT>]
expect() {
  local out got=0 outputs="$DIR/$1.out"
  RAN=$((RAN + 1))
  : > "$outputs"
  out="$(RESOLVE_CMD="$4" GITHUB_OUTPUT="$outputs" bash "$CHECK" "$3" 2>&1)" || got=$?
  if [ "$got" != "$2" ]; then
    echo "FAIL $1: exit $got, expected $2. Output: $out"
    FAILED=1
  elif ! grep -qF -- "$5" <<< "$out"; then
    echo "FAIL $1: output lacks '$5'. Output: $out"
    FAILED=1
  elif [ -n "${6:-}" ] && ! grep -qxF -- "$6" "$outputs"; then
    echo "FAIL $1: GITHUB_OUTPUT lacks the line '$6'"
    FAILED=1
  elif [ -z "${6:-}" ] && [ -s "$outputs" ]; then
    echo "FAIL $1: wrote GITHUB_OUTPUT, which only drift may do"
    FAILED=1
  else
    echo "ok   $1"
  fi
}

SAME="$(dockerfile same "$A" "$A" "$A")"
expect same 0 "$SAME" "echo $A" "is still $A"
expect drifted 1 "$SAME" "echo $B" "is now $B" "current=$B"
expect drifted-reports-pin 1 "$SAME" "echo $B" "pins $A" "pinned=$A"
expect lookup-fails 2 "$SAME" "exit 1" "could not resolve"
expect lookup-empty 2 "$SAME" "true" "not a sha256 digest"
expect lookup-uppercase 2 "$SAME" "echo ${A^^}" "not a sha256 digest"
expect split-pin 2 "$(dockerfile split "$A" "$B" "$A")" "echo $A" "exactly one digest"
printf 'FROM ubuntu:24.04 AS build-php\n' > "$DIR/unpinned.Dockerfile"
expect unpinned 2 "$DIR/unpinned.Dockerfile" "echo $A" "found: none"

if [ "$RAN" -ne "$EXPECTED_CASES" ]; then
  echo "FAIL $RAN of $EXPECTED_CASES cases ran"
  FAILED=1
fi
exit "$FAILED"
