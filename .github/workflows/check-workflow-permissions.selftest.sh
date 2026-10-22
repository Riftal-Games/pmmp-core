#!/usr/bin/env bash
# Runs check-workflow-permissions.sh against fixture directories and the real
# workflows, so a check that stopped telling the expected scopes from a
# missing, dropped or widened one fails here instead of passing quietly.
set -uo pipefail

HERE="$(dirname "$0")"
CHECK="$HERE/check-workflow-permissions.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

report() {
  local name="$1" got="$2" want="$3" out="$4" pattern="$5"
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    FAILED=1
  elif ! grep -qF -- "$pattern" <<< "$out"; then
    echo "FAIL $name: output lacks '$pattern'"
    FAILED=1
  else
    echo "ok   $name"
  fi
}

# expect <exit> <case> <output fragment> <expected list> <workflow body>
expect() {
  local want="$1" name="$2" pattern="$3" out got=0
  mkdir "$DIR/$name"
  printf '%s\n' "$4" > "$DIR/$name/expected.txt"
  printf '%s\n' "$5" > "$DIR/$name/w.yml"
  out="$(bash "$CHECK" "$DIR/$name/expected.txt" "$DIR/$name" 2>&1)" || got=$?
  report "$name" "$got" "$want" "$out" "$pattern"
}

JOBS="jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo 'permissions: write-all'
  b:
    runs-on: ubuntu-latest
    steps:
      - run: true"
TOP="on: push
# why the scopes are what they are
permissions:
  issues: read  # a trailing comment is not a scope
  pull-requests: write

$JOBS"
WANT="# workflow, where, scope
w.yml workflow issues:read
w.yml workflow pull-requests:write"
PERJOB="jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - run: true
  b:
    permissions: {}
    runs-on: ubuntu-latest"
WANTJOB="w.yml job:a contents:write
w.yml job:b {}"

expect 0 top-level "declare exactly" "$WANT" "$TOP"
expect 0 every-job "declare exactly" "$WANTJOB" "$PERJOB"
expect 0 empty-scopes "declare exactly" "w.yml workflow {}" "permissions: {}
$JOBS"
expect 1 no-block "job a has no permissions: block" "$WANT" "on: push
$JOBS"
expect 1 one-job-bare "job b has no permissions: block" "w.yml job:a contents:write" \
  "${JOBS/runs-on: ubuntu-latest/runs-on: ubuntu-latest
    permissions:
      contents: write}"
expect 1 no-jobs "no job found under jobs:" "$WANT" "on: push"
expect 1 scope-dropped "expected but not declared: w.yml workflow issues:read" "$WANT" \
  "${TOP/  issues: read  # a trailing comment is not a scope
/}"
expect 1 scope-commented-out "expected but not declared: w.yml workflow issues:read" "$WANT" \
  "${TOP/  issues: read/  # issues: read}"
expect 1 scope-widened "declared but not expected: w.yml workflow issues:write" "$WANT" \
  "${TOP/issues: read/issues: write}"
expect 1 scope-extra "declared but not expected: w.yml workflow contents:write" "$WANT" \
  "${TOP/  pull-requests: write/  pull-requests: write
  contents: write}"
expect 1 scope-twice "scope issues twice" "$WANT" "${TOP/  pull-requests: write/  pull-requests: write
  issues: read}"
expect 1 write-all "not a block mapping or {}: write-all" "$WANT" "permissions: write-all
$JOBS"
expect 1 flow-mapping "not a block mapping or {}" "$WANT" "permissions: { issues: read }
$JOBS"
expect 1 empty-block "empty permissions: block for workflow" "$WANT" "permissions:
$JOBS"
expect 1 not-a-scope "not a name: level scope" "$WANT" "${TOP/issues: read/issues: maybe}"
expect 1 second-block "second permissions: key for workflow" "$WANT" "$TOP
permissions: {}"
expect 1 job-overrides "declared but not expected: w.yml job:a contents:write" "$WANT" \
  "${TOP/"$JOBS"/"$PERJOB"}"
expect 1 workflow-not-listed "declared but not expected: w.yml workflow issues:read" \
  "other.yml workflow {}" "$TOP"
expect 1 listed-workflow-missing "expected but not declared: gone.yml workflow {}" \
  "$WANT
gone.yml workflow {}" "$TOP"

mkdir "$DIR/crlf"
printf '%s\n' "$WANT" | sed 's/$/\r/' > "$DIR/crlf/expected.txt"
printf '%s\n' "$TOP" | sed 's/$/\r/' > "$DIR/crlf/w.yml"
got=0
out="$(bash "$CHECK" "$DIR/crlf/expected.txt" "$DIR/crlf" 2>&1)" || got=$?
report crlf "$got" 0 "$out" "declare exactly"

mkdir "$DIR/yaml"
printf '%s\n' "$WANT" > "$DIR/yaml/expected.txt"
printf 'on: push\n%s\n' "$JOBS" > "$DIR/yaml/w.yaml"
got=0
out="$(bash "$CHECK" "$DIR/yaml/expected.txt" "$DIR/yaml" 2>&1)" || got=$?
report yaml-extension "$got" 1 "$out" "w.yaml"

mkdir "$DIR/none"
got=0
out="$(bash "$CHECK" "$DIR/crlf/expected.txt" "$DIR/none" 2>&1)" || got=$?
report no-workflows "$got" 1 "$out" "no workflow files"

got=0
out="$(bash "$CHECK" "$DIR/missing.txt" "$DIR/crlf" 2>&1)" || got=$?
report no-expected-list "$got" 1 "$out" "no expected list"

got=0
out="$(bash "$CHECK" "$HERE/workflow-permissions.expected" "$HERE" 2>&1)" || got=$?
report real-workflows "$got" 0 "$out" "declare exactly"

# actions/stale lists pull requests through the issues endpoint, so a
# pr-stale.yml that loses issues: read fails only on its next manual
# dispatch unless this check catches it first.
mkdir "$DIR/real"
cp "$HERE"/*.yml "$DIR/real/"
sed -i '/^  issues: read/d' "$DIR/real/pr-stale.yml"
got=0
out="$(bash "$CHECK" "$HERE/workflow-permissions.expected" "$DIR/real" 2>&1)" || got=$?
report pr-stale-drops-issues-read "$got" 1 "$out" "expected but not declared: pr-stale.yml workflow issues:read"

exit "$FAILED"
