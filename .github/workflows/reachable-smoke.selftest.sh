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
  inspect)
    echo "vol-data vol-plugins "
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
exit "${STUB_PING_STATUS:-0}"
EOF
chmod +x "$DIR/bin/docker" "$DIR/bin/python3"

# expect <exit status> <case name> <text the output must contain> [VAR=value...]
expect() {
  local want="$1" name="$2" text="$3" got=0
  shift 3
  mkdir "$DIR/$name"
  env PATH="$DIR/bin:$PATH" STUB_STATE="$DIR/$name" "$@" \
    bash "$SMOKE" image "smoke-$name" 19132 motd > "$DIR/$name/out" 2>&1 || got=$?
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

expect 0 healthy "REACHABLE confirmed on 19132/udp"
expect 1 container-exit-1 "server exited with code 1 after 'stop'" STUB_WAIT=1
expect 1 docker-run-exit-3 "docker run exited 3 after 'stop'" STUB_RUN_STATUS=3
expect 1 wait-timeout "server did not shut down cleanly" STUB_WAIT=hang
expect 1 no-pong "NOT REACHABLE" STUB_PING_STATUS=1
expect 1 volume-outlived "anonymous volume vol-data outlived" STUB_KEEP_VOLUMES=1

exit "$FAILED"
