#!/usr/bin/env bash
# Runs check-publish-ref.sh inside a throwaway repository, so a check that
# stopped telling the tag's tree from a dispatched branch's fails here instead
# of letting the publish workflow push a mislabelled image.
set -uo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/check-publish-ref.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

g() {
  git -C "$DIR" -c user.name=selftest -c user.email=selftest@invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@" > /dev/null 2>&1
}

g init -q -b riftal
g commit -q --allow-empty -m tagged
TAGGED="$(git -C "$DIR" rev-parse HEAD)"
g tag 1.0.0
g tag -a -m annotated 1.0.0-annotated
g commit -q --allow-empty -m later
LATER="$(git -C "$DIR" rev-parse HEAD)"

expect() {
  local want="$1" name="$2" head="$3" out got=0
  shift 3
  g checkout -q --detach "$head"
  out="$(cd "$DIR" && bash "$CHECK" "$@" 2> /dev/null)" || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    FAILED=1
  elif [ "$want" = 0 ] && [ "$out" != "$TAGGED" ]; then
    echo "FAIL $name: printed '$out', expected $TAGGED"
    FAILED=1
  else
    echo "ok   $name"
  fi
}

expect 0 on-the-tag "$TAGGED" 1.0.0
expect 0 on-an-annotated-tag "$TAGGED" 1.0.0-annotated
expect 1 dispatched-branch-ahead-of-tag "$LATER" 1.0.0
expect 1 dispatched-branch-named-as-release "$LATER" riftal
expect 1 no-such-tag "$TAGGED" 9.9.9
expect 2 empty-tag "$TAGGED" ""
expect 2 no-arguments "$TAGGED"

exit "$FAILED"
