#!/usr/bin/env bash
# Self-test for check-ubuntu-base.sh.
#
# docker/Dockerfile never chains a `FROM <stage> AS <name>` off an earlier
# stage and never uses `--platform=`, so a CI run against it alone proves
# nothing about either branch pmmp-core#66 added. These fixtures exercise
# both branches directly, the bad-external-base case pmmp-core#21/#65 fixed,
# and each way a digest pin can be missing, malformed or split across stages
# (pmmp-core#19), so a revert of any of them turns this red on the same commit.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-ubuntu-base.sh"
FIXTURES="$SCRIPT_DIR/ci-fixtures"
FAILURES=0
PASSES=0
# Every assertion below must run. A harness that quietly skips one and still
# prints its closing line is the exact failure it exists to catch.
EXPECTED_ASSERTIONS=13

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

# Fixtures that must be flagged on exactly one line, the one that begins with
# $3. $3 starts with the line number, so a checker that flags a clean line
# instead of the bad one, or as well as it, fails here too.
expect_flagged() {
  local out
  run_check "$FIXTURES/$1" "$2" || return 0
  if [[ "$out" == "$3"* && "$out" != *$'\n'* ]]; then
    pass "$1 -> flagged, naming $3"
  else
    fail "expected $1 to flag only the line beginning '$3' on Ubuntu $2, got:"
    printf '%s\n' "$out"
  fi
}

expect_clean chained-stage.Dockerfile 24.04
expect_clean platform-prefixed.Dockerfile 24.04
expect_flagged bad-external-base.Dockerfile 24.04 "2:FROM ubuntu:22.04@sha256:"
expect_flagged unpinned-base.Dockerfile 24.04 "2:FROM ubuntu:24.04 AS build-pocketmine"
# The malformed digest is on the first stage. On a later stage the shared
# digest rule would flag it too, and the format rule could go unproven.
expect_flagged short-digest.Dockerfile 24.04 "1:FROM ubuntu:24.04@sha256:68ee22004a91 AS"
expect_flagged uppercase-digest.Dockerfile 24.04 "1:FROM ubuntu:24.04@sha256:68EE"
expect_flagged mixed-digests.Dockerfile 24.04 "2:FROM ubuntu:24.04@sha256:0123"

# Five base lines a FROM ubuntu: filter or a regex match on the tag would
# accept (#65). A tagless digest or a build arg may well resolve to 24.04, but
# the check cannot see that from the text, so it has to refuse them. Every
# other external stage in these fixtures shares one well-formed digest, so the
# bypass is the only line the check has any reason to print.
expect_flagged debian-stage.Dockerfile 24.04 "1:FROM debian:12@sha256:"
expect_flagged digest-pin.Dockerfile 24.04 "3:FROM ubuntu@sha256:"
# The fixture's own text, matched verbatim, so the build arg must not expand.
# shellcheck disable=SC2016
expect_flagged build-arg-base.Dockerfile 24.04 '3:FROM ${BASE_IMAGE} AS build-pocketmine'
expect_flagged extra-spaces.Dockerfile 24.04 "2:FROM  ubuntu:22.04@sha256:"
expect_flagged unescaped-dot.Dockerfile 24.04 "2:FROM ubuntu:24x04@sha256:"

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
printf 'all %s assertions passed: stage chaining, --platform stripping, the bad-external-base regression, the digest-pin format, the five #65 bypasses, and the real Dockerfile.\n' "$PASSES"
