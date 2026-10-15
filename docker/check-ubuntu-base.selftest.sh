#!/usr/bin/env bash
# Self-test for check-ubuntu-base.sh.
#
# docker/Dockerfile never chains a `FROM <stage> AS <name>` off an earlier
# stage and never uses `--platform=`, so a CI run against it alone proves
# nothing about either branch pmmp-core#66 added. These fixtures exercise
# both branches directly, plus the bad-external-base case pmmp-core#21/#65
# fixed, so a revert of either fix turns this red on the same commit.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-ubuntu-base.sh"
FIXTURES="$SCRIPT_DIR/ci-fixtures"
FAILURES=0
PASSES=0
# Every assertion below must run. A harness that quietly skips one and still
# prints its closing line is the exact failure it exists to catch.
EXPECTED_ASSERTIONS=4

pass() { printf '  ok    %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf '::error::%s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# Runs the check on $1 against Ubuntu $2 and leaves its stdout in the caller's
# `out`. The check always exits 0, so any other status is a failed assertion:
# a check that crashes prints nothing, and nothing is what a clean file prints.
run_check() {
  local status
  out="$("$CHECK" "$1" "$2")"
  status=$?
  if [ "$status" -ne 0 ]; then
    fail "check-ubuntu-base.sh exited $status on $1, and it must always exit 0. It printed:"
    printf '%s\n' "$out"
    return 1
  fi
}

# Fixtures that must be recognized as fully on $2, so the check must print
# nothing for them.
expect_clean() {
  local out
  run_check "$FIXTURES/$1" "$2" || return 0
  if [ -z "$out" ]; then
    pass "$1 -> no stragglers"
  else
    fail "expected $1 to have no stragglers on Ubuntu $2, got:"
    printf '%s\n' "$out"
  fi
}

# Fixtures that must still be flagged, naming the exact bad line so a checker
# that stops matching for an unrelated reason cannot pass by accident.
expect_flagged() {
  local out
  run_check "$FIXTURES/$1" "$2" || return 0
  if [ -n "$out" ] && printf '%s' "$out" | grep -qF "$3"; then
    pass "$1 -> flagged, naming $3"
  else
    fail "expected $1 to flag a line containing '$3' on Ubuntu $2, got:"
    printf '%s\n' "$out"
  fi
}

expect_clean chained-stage.Dockerfile 24.04
expect_clean platform-prefixed.Dockerfile 24.04
expect_flagged bad-external-base.Dockerfile 24.04 "FROM ubuntu:22.04 AS build-pocketmine"

# The real Dockerfile is the thing production ships. Passing on the fixtures
# above is worthless if the same logic no longer agrees with the file it was
# extracted from.
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if run_check "$REPO_ROOT/docker/Dockerfile" 24.04; then
  if [ -z "$out" ]; then
    pass "docker/Dockerfile -> no stragglers"
  else
    fail "expected docker/Dockerfile to have no stragglers on Ubuntu 24.04, got:"
    printf '%s\n' "$out"
  fi
fi

printf '\n'
ran=$((PASSES + FAILURES))
if [ "$ran" -ne "$EXPECTED_ASSERTIONS" ]; then
  printf '%s of %s assertions ran, so one did not run and cannot have passed\n' \
    "$ran" "$EXPECTED_ASSERTIONS"
  exit 1
fi
if [ "$FAILURES" -ne 0 ]; then
  printf '%s self-test assertion(s) failed. The stage-walk check has stopped discriminating.\n' "$FAILURES"
  exit 1
fi
printf 'all %s assertions passed: stage chaining, --platform stripping, the bad-external-base regression, and the real Dockerfile.\n' "$PASSES"
