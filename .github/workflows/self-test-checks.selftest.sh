#!/usr/bin/env bash
# Runs self-test-checks.sh against throwaway trees, so a gate that stopped
# finding, running or failing self-tests fails here instead of letting the
# publish workflow build on checks nobody proved. Each tree carries passing
# stubs for the workflow checks the gate runs last, so a case fails only for
# the reason it names. No tree holds this file, so the gate never recurses.
set -uo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/self-test-checks.sh"
DIR="$(mktemp -d)"
trap 'chmod -R u+rwx "$DIR"; rm -rf "$DIR"' EXIT
FAILED=0

tree() {
  local root="$DIR/$1" stub
  mkdir -p "$root/docker" "$root/.github/workflows"
  for stub in check-auto-report-flag check-build-timeout check-run-expressions check-support-permissions check-dockerfile-eol check-pinned-image; do
    echo 'exit 0' > "$root/.github/workflows/$stub.sh"
  done
  echo "$root"
}

expect() {
  local want="$1" name="$2" root="$3" pattern="$4" out got=0
  out="$(SELFTEST_ROOT="$root" bash "$CHECK" 2>&1)" || got=$?
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

ROOT="$(tree clean)"
echo 'exit 0' > "$ROOT/docker/ok.selftest.sh"
echo 'exit 0' > "$ROOT/.github/workflows/ok.selftest.sh"
expect 0 clean-tree "$ROOT" "found 2 self-test(s)"

ROOT="$(tree nested)"
mkdir -p "$ROOT/docker/a/b"
echo 'touch ran-nested' > "$ROOT/docker/a/b/nested.selftest.sh"
expect 0 nested-self-test-runs "$ROOT" "bash docker/a/b/nested.selftest.sh"
if [ ! -e "$ROOT/ran-nested" ]; then
  echo "FAIL nested-self-test-runs: listed but never ran"
  FAILED=1
fi

ROOT="$(tree pycache)"
echo 'exit 0' > "$ROOT/.github/workflows/ok.selftest.sh"
mkdir "$ROOT/.github/workflows/__pycache__"
echo 'compiled' > "$ROOT/.github/workflows/__pycache__/x.selftest.cpython-312.pyc"
expect 0 pycache-ignored "$ROOT" "found 1 self-test(s)"

ROOT="$(tree ruby)"
echo 'exit 0' > "$ROOT/docker/ok.selftest.sh"
echo 'exit 0' > "$ROOT/docker/x.selftest.rb"
expect 1 no-runner-fails "$ROOT" "docker/x.selftest.rb is named as a self-test but has no runner"

# A Windows checkout under Git Bash cannot always create a symlink or deny a
# directory read. Only there may a case that cannot hold be skipped; anywhere
# else the case runs and fails on its own terms.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;;
  *) WINDOWS=0 ;;
esac

ROOT="$(tree dangling)"
echo 'exit 0' > "$ROOT/docker/ok.selftest.sh"
ln -s missing.sh "$ROOT/docker/gone.selftest.sh" 2>/dev/null
if [ "$WINDOWS" = 1 ] && [ ! -L "$ROOT/docker/gone.selftest.sh" ]; then
  echo "skip dangling-symlink-fails: this Windows checkout cannot create a symlink"
else
  expect 1 dangling-symlink-fails "$ROOT" "::error::bash docker/gone.selftest.sh failed"
fi

ROOT="$(tree empty)"
expect 1 empty-tree-fails "$ROOT" "no self-tests found"

# Root bypasses the permission on a chmod 000 directory, so find never errors
# and the case cannot exercise the path it names.
if [ "$(id -u)" = 0 ]; then
  echo "skip unreadable-directory-fails: running as root, where chmod 000 does not stop find"
else
  ROOT="$(tree unreadable)"
  echo 'exit 0' > "$ROOT/docker/ok.selftest.sh"
  mkdir "$ROOT/docker/locked"
  echo 'exit 1' > "$ROOT/docker/locked/hidden.selftest.sh"
  chmod 000 "$ROOT/docker/locked"
  if [ "$WINDOWS" = 1 ] && ls "$ROOT/docker/locked" > /dev/null 2>&1; then
    echo "skip unreadable-directory-fails: chmod 000 does not stop a read on this Windows checkout"
  else
    expect 1 unreadable-directory-fails "$ROOT" "find could not search every directory"
  fi
fi

exit "$FAILED"
