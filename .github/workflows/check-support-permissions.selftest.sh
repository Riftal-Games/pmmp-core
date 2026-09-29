#!/usr/bin/env bash
# Runs check-support-permissions.sh against fixture workflows and the real
# support.yml, so a check that stopped telling issues: write alone from a
# missing or widened scope fails here instead of passing quietly.
set -uo pipefail

HERE="$(dirname "$0")"
CHECK="$HERE/check-support-permissions.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

report() {
  if [ "$2" != "$3" ]; then
    echo "FAIL $1: exit $2, expected $3"
    FAILED=1
  else
    echo "ok   $1"
  fi
}

expect() {
  local want="$1" name="$2" body="$3" got=0
  printf '%s\n' "$body" > "$DIR/$name.yml"
  bash "$CHECK" "$DIR/$name.yml" > /dev/null 2>&1 || got=$?
  report "$name" "$got" "$want"
}

JOBS="$(cat <<'EOF'
jobs:
  support:
    runs-on: ubuntu-latest
    steps:
      - uses: dessant/support-requests@v5
EOF
)"

SCOPED="$(cat <<'EOF'
on:
  issues:
# why the scope is what it is
permissions:
  issues: write

EOF
)
$JOBS"

expect 0 scoped "$SCOPED"
expect 1 no-block "on:
  issues:
$JOBS"
expect 1 write-all "permissions: write-all
$JOBS"
expect 1 flow-mapping "permissions: { issues: write }
$JOBS"
expect 1 empty-block "permissions:
$JOBS"
expect 1 issues-read "${SCOPED/issues: write/issues: read}"
expect 1 extra-scope "${SCOPED/issues: write/issues: write
  contents: write}"
expect 1 commented-out "${SCOPED/  issues: write/  # issues: write}"
expect 1 duplicate-block "$SCOPED
permissions:
  issues: write"
expect 1 job-level "${SCOPED/runs-on: ubuntu-latest/runs-on: ubuntu-latest
    permissions: write-all}"

printf '%s\n' "$SCOPED" | sed 's/$/\r/' > "$DIR/crlf.yml"
got=0
bash "$CHECK" "$DIR/crlf.yml" > /dev/null 2>&1 || got=$?
report crlf "$got" 0

got=0
bash "$CHECK" "$DIR/missing-file.yml" > /dev/null 2>&1 || got=$?
report missing-file "$got" 1

got=0
bash "$CHECK" "$HERE/support.yml" > /dev/null 2>&1 || got=$?
report support.yml "$got" 0

exit "$FAILED"
