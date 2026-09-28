#!/usr/bin/env bash
# Runs check-build-timeout.sh against fixture workflows, so a check that
# stopped telling a step-level timeout from a missing or misplaced one fails
# here instead of passing both workflow files quietly.
set -uo pipefail

CHECK="$(dirname "$0")/check-build-timeout.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

expect() {
  local want="$1" name="$2" body="$3" got=0
  printf '%s\n' "$body" > "$DIR/$name.yml"
  bash "$CHECK" "$DIR/$name.yml" > /dev/null 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    FAILED=1
  else
    echo "ok   $name"
  fi
}

PRESENT="$(cat <<'EOF'
jobs:
  build:
    steps:
    - uses: actions/checkout@v7
    - name: Build
      timeout-minutes: 55
      uses: docker/build-push-action@v7.3.0
      with:
        push: false
    - name: After
      run: echo done
EOF
)"

PRESENT_DEEPER="$(cat <<'EOF'
jobs:
  publish:
    steps:
      - name: Build
        uses: docker/build-push-action@v7.3.0
        with:
          push: false
        timeout-minutes: 55
EOF
)"

MISSING="$(cat <<'EOF'
jobs:
  build:
    steps:
    - name: Build
      uses: docker/build-push-action@v7.3.0
      with:
        push: false
    - name: After
      timeout-minutes: 5
      run: echo done
EOF
)"

UNDER_WITH="$(cat <<'EOF'
jobs:
  build:
    steps:
    - name: Build
      uses: docker/build-push-action@v7.3.0
      with:
        timeout-minutes: 55
        push: false
EOF
)"

COMMENTED="$(cat <<'EOF'
jobs:
  build:
    steps:
    - name: Build
      # timeout-minutes: 55
      uses: docker/build-push-action@v7.3.0
EOF
)"

SECOND_JOB_MISSING="$(cat <<'EOF'
jobs:
  build:
    steps:
    - name: Build
      timeout-minutes: 55
      uses: docker/build-push-action@v7.3.0
  again:
    steps:
    - uses: docker/build-push-action@v7.3.0
EOF
)"

expect 0 present "$PRESENT"
expect 0 present-deeper-list "$PRESENT_DEEPER"
expect 1 missing "$MISSING"
expect 1 under-with "$UNDER_WITH"
expect 1 commented-out "$COMMENTED"
expect 1 zero "${PRESENT/timeout-minutes: 55/timeout-minutes: 0}"
expect 1 second-job-missing "$SECOND_JOB_MISSING"
expect 1 end-of-line-comment "$(cat <<'EOF'
jobs:
  build:
    steps:
    - name: Build # timeout-minutes: 55
      uses: docker/build-push-action@v7.3.0
EOF
)"
expect 1 second-double-quoted-missing "$(cat <<'EOF'
jobs:
  build:
    steps:
    - timeout-minutes: 55
      uses: docker/build-push-action@v7.3.0
    - uses: "docker/build-push-action@v7.3.0"
EOF
)"
expect 1 second-single-quoted-missing "$(cat <<'EOF'
jobs:
  build:
    steps:
    - timeout-minutes: 55
      uses: docker/build-push-action@v7.3.0
    - uses: 'docker/build-push-action@v7.3.0'
EOF
)"
expect 1 no-build-step "$(cat <<'EOF'
jobs:
  build:
    steps:
    - uses: actions/checkout@v7
EOF
)"

got=0
bash "$CHECK" "$DIR/missing-file.yml" > /dev/null 2>&1 || got=$?
if [ "$got" != 1 ]; then
  echo "FAIL missing-file: exit $got, expected 1"
  FAILED=1
else
  echo "ok   missing-file"
fi

exit "$FAILED"
