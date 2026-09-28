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

cd "$(dirname "$0")/../.." || exit 1
shopt -s nullglob
FAILED=0

run() {
  echo "::group::$*"
  if ! "$@"; then
    echo "::error::$* failed"
    FAILED=1
  fi
  echo "::endgroup::"
}

TESTS=(docker/*.selftest.sh docker/*.selftest.py .github/workflows/*.selftest.sh .github/workflows/*.selftest.py)
if [ "${#TESTS[@]}" = 0 ]; then
  echo "::error::no self-tests found, so no checking script was proven"
  exit 1
fi

for TEST in "${TESTS[@]}"; do
  case "$TEST" in
    *.py) run python3 "$TEST" ;;
    *) run bash "$TEST" ;;
  esac
done

# The publish workflow has no pull_request run, so it is only ever checked
# from here. The two smoke scripts carry boot lines of their own.
WORKFLOWS=(.github/workflows/docker-image-ci.yml .github/workflows/docker-image-publish.yml)
run bash .github/workflows/check-auto-report-flag.sh "${WORKFLOWS[@]}" .github/workflows/reachable-smoke.sh .github/workflows/crash-boot-smoke.sh
run bash .github/workflows/check-build-timeout.sh "${WORKFLOWS[@]}"
run bash .github/workflows/check-run-expressions.sh .github/workflows/docker-image-publish.yml

echo "ran ${#TESTS[@]} self-test(s) and the workflow checks"
exit "$FAILED"
