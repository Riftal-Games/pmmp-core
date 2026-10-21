#!/usr/bin/env bash
# Runs reachable-smoke.sh against stub `docker` and `python3` commands, so a
# verdict it should reach only on a broken server is proven here. CI's real
# boot exits 0 on `stop`, which would pass a script that never looked.
set -uo pipefail

SMOKE="$(cd "$(dirname "$0")" && pwd)/reachable-smoke.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

mkdir "$DIR/bin"
cat > "$DIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  run)
    printf '%s\n' "$@" > "$STUB_STATE/run-args"
    # The real CLI ends when `docker stop` kills the container. This stub
    # ends on EOF instead, which needs it to drop the console write end it
    # inherited from the smoke script.
    exec 3>&-
    echo '[12:00:01.000] [Server thread/INFO]: Done (1.000s)! For help, type "help" or "?"'
    while IFS= read -r line; do
      [ "$line" = stop ] && break
    done
    exit "${STUB_RUN_STATUS:-0}"
    ;;
  wait)
    # 124 is what `timeout` returns when docker wait outlives it.
    [ "${STUB_WAIT:-0}" = hang ] && exit 124
    echo "${STUB_WAIT:-0}"
    ;;
  port)
    printf '%s' "${STUB_PORT-127.0.0.1:41234}"
    ;;
  inspect)
    if [ -n "${STUB_INSPECT_FAILS:-}" ]; then
      echo "Error: No such object: ${*: -1}" >&2
      exit 1
    fi
    echo "${STUB_VOLUMES-vol-data vol-plugins }"
    ;;
  rm)
    [ -n "${STUB_KEEP_VOLUMES:-}" ] || touch "$STUB_STATE/removed"
    ;;
  volume)
    [ ! -e "$STUB_STATE/removed" ]
    ;;
esac
EOF
cat > "$DIR/bin/python3" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_STATE/ping-args"
exit "${STUB_PING_STATUS:-0}"
EOF
chmod +x "$DIR/bin/docker" "$DIR/bin/python3"

# expect <exit status> <case name> <text the output must contain> [VAR=value...]
expect() {
  local want="$1" name="$2" text="$3" got=0
  shift 3
  mkdir "$DIR/$name"
  env PATH="$DIR/bin:$PATH" STUB_STATE="$DIR/$name" "$@" \
    bash "$SMOKE" image "smoke-$name" motd > "$DIR/$name/out" 2>&1 || got=$?
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

expect 0 healthy "REACHABLE confirmed on 41234/udp"
expect 1 no-binding "docker reported no loopback port" STUB_PORT=
expect 1 wildcard-binding "docker reported no loopback port" STUB_PORT=0.0.0.0:41234
expect 1 container-exit-1 "server exited with code 1 after 'stop'" STUB_WAIT=1
expect 1 docker-run-exit-3 "docker run exited 3 after 'stop'" STUB_RUN_STATUS=3
expect 1 wait-timeout "server did not shut down cleanly" STUB_WAIT=hang
expect 1 no-pong "NOT REACHABLE" STUB_PING_STATUS=1
expect 1 volume-outlived "anonymous volume vol-data outlived" STUB_KEEP_VOLUMES=1
expect 0 volumes-removed "anonymous volumes checked: vol-data vol-plugins, all removed"
expect 1 one-volume "expected 2 anonymous volumes on smoke-one-volume, found 1" STUB_VOLUMES=vol-data
expect 1 no-volumes "expected 2 anonymous volumes on smoke-no-volumes, found 0" STUB_VOLUMES=
expect 1 inspect-fails "docker inspect failed on smoke-inspect-fails" STUB_INSPECT_FAILS=1

# Cleanup closes the console FIFO with stderr discarded, and that must not
# discard the reason docker gives for a failed inspect.
if ! grep -qF "No such object: smoke-inspect-fails" "$DIR/inspect-fails/out"; then
  echo "FAIL inspect-stderr: docker's own error for the failed inspect is missing"
  cat "$DIR/inspect-fails/out"
  FAILED=1
else
  echo "ok   inspect-stderr"
fi

# A fixed host port is shared by every matrix leg and job of one run, so the
# run must leave the port to the daemon and ping the one it reports (#64).
if ! grep -qxF -- 127.0.0.1::19132/udp "$DIR/healthy/run-args"; then
  echo "FAIL publish: docker run did not leave the loopback port to the daemon"
  cat "$DIR/healthy/run-args"
  FAILED=1
elif ! grep -qxF 41234 "$DIR/healthy/ping-args"; then
  echo "FAIL ping: raknet-ping.py was not pointed at the port docker reported"
  cat "$DIR/healthy/ping-args"
  FAILED=1
else
  echo "ok   daemon-port"
fi

exit "$FAILED"
