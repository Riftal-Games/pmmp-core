#!/usr/bin/env bash
# Runs crash-boot-smoke.sh against a stub `docker`, so the verdicts it should
# reach only on a hung or misreported crash are proven here. CI's real crash
# boot exits non-zero, which would pass a script that never looked.
set -uo pipefail

SMOKE="$(cd "$(dirname "$0")" && pwd)/crash-boot-smoke.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

mkdir "$DIR/bin"
cat > "$DIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  run)
    # A crash boot that can reach a network or the shipped archive host is
    # the one that can leak a dump, so the stub refuses to start it.
    if [[ " $* " != *" --network none "* || " $* " != *" --auto-report.host=127.0.0.1:9 "* ]]; then
      echo "stub docker: crash boot not isolated: $*" >&2
      exit 125
    fi
    echo 0123456789ab
    ;;
  wait)
    [ "${STUB_EXIT:-}" = hang ] && exec sleep 30
    echo "${STUB_EXIT:-137}"
    ;;
  logs)
    if [ -z "${STUB_NO_CRASH:-}" ]; then
      echo '[12:00:01.000] [Server thread/EMERGENCY]: An unrecoverable error has occurred and the server has crashed. Creating a crash dump'
    fi
    if [ -n "${STUB_UPLOAD:-}" ]; then
      echo '[12:00:01.000] [Server thread/EMERGENCY]: The crash dump has been automatically submitted to the Crash Archive.'
    fi
    ;;
esac
EOF
chmod +x "$DIR/bin/docker"

# expect <exit status> <case name> <text the output must contain> [VAR=value...]
expect() {
  local want="$1" name="$2" text="$3" got=0
  shift 3
  mkdir "$DIR/$name"
  env PATH="$DIR/bin:$PATH" CRASH_EXIT_LIMIT=2 "$@" \
    bash "$SMOKE" image "smoke-$name" plugins > "$DIR/$name/out" 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    FAILED=1
  elif ! grep -qF -- "$text" "$DIR/$name/out"; then
    echo "FAIL $name: output lacks: $text"
    FAILED=1
  else
    echo "ok   $name"
    return
  fi
  cat "$DIR/$name/out"
}

expect 0 crash-exits "crashed server exited 137 on its own"
expect 1 crash-hangs "still running 2s after crashing" STUB_EXIT=hang
expect 1 crash-exits-0 "exited 0 after crashing" STUB_EXIT=0
expect 1 never-crashed "never logged a crash" STUB_NO_CRASH=1
expect 1 uploaded "attempted a crash archive upload" STUB_UPLOAD=1

exit "$FAILED"
