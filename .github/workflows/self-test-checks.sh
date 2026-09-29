#!/usr/bin/env bash
# Proves every checking script the image workflows trust can still fail,
# then runs the checks that read the workflow files themselves. Both
# docker-image-ci.yml and docker-image-publish.yml call this before building,
# so a release from a ref that never went through CI cannot pass its publish
# gate on a check that has stopped looking (#73).
#
# Self-tests are found by name, not listed, so one added under either
# directory runs in both workflows without editing either. Every one runs
# even after a failure, so a single run reports all that are broken.
set -uo pipefail

# SELFTEST_ROOT points this at a fixture tree, for self-test-checks.selftest.sh.
cd "${SELFTEST_ROOT:-$(dirname "$0")/../..}" || exit 1
FAILED=0

run() {
  echo "::group::$*"
  if ! "$@"; then
    echo "::error::$* failed"
    FAILED=1
  fi
  echo "::endgroup::"
}

# Self-tests are found at any depth, and a *.selftest.* with an extension
# that has no runner below fails the gate. Symlinks are listed so a dangling one fails
# when run, and a directory find cannot read fails the gate outright.
# __pycache__ holds the interpreter's own compiled copies, never a self-test
# anyone wrote.
if ! FOUND=$(find docker .github/workflows -name __pycache__ -prune -o ! -type d -name '*.selftest.*' -print | sort); then
  echo "::error::find could not search every directory, so a self-test may be unlisted"
  FAILED=1
fi
mapfile -t TESTS < <(printf '%s' "$FOUND")
if [ "${#TESTS[@]}" = 0 ]; then
  echo "::error::no self-tests found, so no checking script was proven"
  exit 1
fi

for TEST in "${TESTS[@]}"; do
  case "$TEST" in
    *.selftest.py) run python3 "$TEST" ;;
    *.selftest.sh) run bash "$TEST" ;;
    *)
      echo "::error::$TEST is named as a self-test but has no runner, only .sh and .py run"
      FAILED=1
      ;;
  esac
done

# The publish workflow has no pull_request run, so it is only ever checked
# from here. The two smoke scripts carry boot lines of their own.
WORKFLOWS=(.github/workflows/docker-image-ci.yml .github/workflows/docker-image-publish.yml)
run bash .github/workflows/check-auto-report-flag.sh "${WORKFLOWS[@]}" .github/workflows/reachable-smoke.sh .github/workflows/crash-boot-smoke.sh
run bash .github/workflows/check-build-timeout.sh "${WORKFLOWS[@]}"
run bash .github/workflows/check-run-expressions.sh .github/workflows/docker-image-publish.yml

echo "found ${#TESTS[@]} self-test(s), ran the workflow checks"
exit "$FAILED"
