#!/usr/bin/env bash
# REACHABLE check shared by docker-image-ci.yml and docker-image-publish.yml.
# Boots the image with its UDP port published on a loopback port the docker
# daemon picks, expects a RakNet pong with the given MOTD and the protocol
# below, then stops the server through its console and removes the
# container and its anonymous volumes. A server that exits non-zero after
# `stop` fails the run even when the pong was valid.
#
# The daemon picks the port because a port derived from the run identity is
# shared by every matrix leg and every job of that run, and two of them on
# one daemon collide on the bind (#64). The container name has no such
# fallback, so callers make it unique per job, matrix leg and attempt.
#
# Usage: reachable-smoke.sh <image> <container name> <motd>
set -euo pipefail

if [ "$#" != 3 ]; then
  echo "usage: reachable-smoke.sh <image> <container name> <motd>" >&2
  exit 2
fi
IMAGE="$1"
CONTAINER_NAME="$2"
EXPECTED_MOTD="$3"

# Advertised Bedrock protocol. Derived from ProtocolInfo::CURRENT_PROTOCOL
# in axolotl-pm/bedrock-protocol 62.0.0+bedrock-1.26.50, which
# composer.lock pins. A protocol bump has to move this number
# deliberately, because that is the value that otherwise diverges from
# the client and from the proxy in silence.
EXPECTED_PROTOCOL="2193"

HERE="$(dirname "$0")"
LOG="$(mktemp)"
FIFO="$(mktemp -u)"
mkfifo "$FIFO"
# The server must stay alive while it is pinged, so `echo stop` cannot be
# piped in. Hold stdin open through a FIFO instead, and write `stop` into
# it once the ping is done, so the shutdown stays clean.
exec 3<>"$FIFO"

DOCKER_PID=""
# Runs on every exit from this point, including the readiness-timeout
# `exit 1` below, so a server that never comes up is not left running
# under the runner instead of being torn down with the job.
cleanup() {
  local status=$?
  local mounts="" name survived=0
  local -a volumes=()
  { exec 3>&-; } 2>/dev/null || true
  if [ -n "$DOCKER_PID" ]; then
    docker stop "$CONTAINER_NAME" > /dev/null 2>&1 || true
    wait "$DOCKER_PID" 2>/dev/null || true
  fi
  # docker/Dockerfile declares VOLUME /data and /plugins and this run
  # mounts neither, so the container holds exactly two anonymous
  # volumes. The count guards the survival loop below: a format string
  # that matches nothing, or a renamed `.Type`, yields zero names, and
  # the loop would then pass without checking a single volume.
  #
  # A failed inspect fails the run rather than warning, because a
  # REACHABLE pass is also the claim that no volume was stranded, and
  # without the names nothing backs that claim. docker's own reason
  # goes to the log above the error.
  if mounts=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$CONTAINER_NAME"); then
    read -r -a volumes <<< "$mounts"
    if [ "${#volumes[@]}" != 2 ]; then
      echo "::error::expected 2 anonymous volumes on $CONTAINER_NAME, found ${#volumes[@]}: $mounts"
      status=1
    fi
  else
    echo "::error::docker inspect failed on $CONTAINER_NAME, so its anonymous volumes were not checked"
    status=1
  fi
  docker rm -v "$CONTAINER_NAME" > /dev/null 2>&1 || true
  # A volume that outlives the container is stranded on the daemon
  # for good, and on a self-hosted runner they pile up run after run.
  for name in "${volumes[@]}"; do
    if docker volume inspect "$name" > /dev/null 2>&1; then
      echo "::error::anonymous volume $name outlived docker rm -v $CONTAINER_NAME"
      survived=1
      status=1
    fi
  done
  if [ "${#volumes[@]}" != 0 ] && [ "$survived" = 0 ]; then
    echo "anonymous volumes checked: ${volumes[*]}, all removed by docker rm -v"
  fi
  rm -f "$LOG" "$LOG.clean" "$FIFO"
  exit "$status"
}
trap cleanup EXIT

# --auto-report.enabled=0 and --auto-updater.enabled=0 exactly once: the
# shipped pocketmine.yml posts crash dumps to a public archive and sends an
# update check from every boot, and a repeated flag reaches the server as an
# array, which casts back to true (#91, #96).
docker run --name "$CONTAINER_NAME" -i \
  -p 127.0.0.1::19132/udp \
  -e POCKETMINE_ARGS="--settings.enable-dev-builds=1 --auto-report.enabled=0 --auto-updater.enabled=0 --motd=$EXPECTED_MOTD" \
  "$IMAGE" <"$FIFO" >"$LOG" 2>&1 &
DOCKER_PID=$!

# Readiness is the server's own startFinished line
# (resources/translations/eng.ini: 'Done ({%0}s)! For help, type "help"
# or "?"'), not a fixed sleep and not "the process is alive". This run
# is `docker run -i` with no `-t`, so docker/start.sh leaves ANSI off
# by default; the strip below is a defensive no-op kept in case that
# ever changes. Written as two commands rather than a pipeline because
# `grep -q` exiting early would SIGPIPE the `sed` and `pipefail` would
# then read a match as a miss.
READY=0
for _ in $(seq 1 180); do
  sed 's/\x1b\[[0-9;]*m//g' "$LOG" > "$LOG.clean"
  if grep -qF 'For help, type "help"' "$LOG.clean"; then
    READY=1
    break
  fi
  if ! kill -0 "$DOCKER_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [ "$READY" != 1 ]; then
  echo "::error::server never reached the startFinished line, so there was nothing to ping"
  cat "$LOG"
  "$HERE/check-no-crash-upload.sh" "$LOG"
  exit 1
fi
# `docker port` prints one ADDRESS:PORT line per binding, and the publish
# above makes exactly one.
BINDING=$(docker port "$CONTAINER_NAME" 19132/udp) || BINDING=""
HOST_PORT="${BINDING##*:}"
if ! [[ "$BINDING" == 127.0.0.1:* && "$HOST_PORT" =~ ^[0-9]+$ ]]; then
  echo "::error::docker reported no loopback port for 19132/udp, got: $BINDING"
  cat "$LOG"
  "$HERE/check-no-crash-upload.sh" "$LOG"
  exit 1
fi
echo "server is up, pinging 127.0.0.1:$HOST_PORT/udp"

PING_STATUS=0
python3 "$HERE/raknet-ping.py" 127.0.0.1 "$HOST_PORT" \
  --expect-motd "$EXPECTED_MOTD" \
  --expect-protocol "$EXPECTED_PROTOCOL" || PING_STATUS=$?

# Shut down through the console `stop` command before reporting any
# verdict, so the run never ends on an abrupt termination. `stop`
# comes before the job-control `wait`: that wait blocks on the
# backgrounded `docker run` exiting, and a server ignoring the
# console `stop` would otherwise leave it blocked on a process
# nothing had yet asked to exit, turning the "did not shut down
# cleanly" verdict below into a job timeout instead.
echo stop >&3
exec 3>&-
SHUTDOWN_STATUS=0
# `docker wait` exits 0 whatever the container did and prints the
# container's exit code instead. PocketMine exits 0 on a console `stop`.
EXIT_CODE=$(timeout 120 docker wait "$CONTAINER_NAME") || SHUTDOWN_STATUS=$?
docker stop "$CONTAINER_NAME" > /dev/null 2>&1 || true
RUN_STATUS=0
wait "$DOCKER_PID" || RUN_STATUS=$?

echo "--- server log ---"
cat "$LOG"
echo "--- end server log ---"
"$HERE/check-no-crash-upload.sh" "$LOG"

if [ "$PING_STATUS" != 0 ]; then
  echo "::error::NOT REACHABLE: no valid RakNet unconnected pong on $HOST_PORT/udp"
  exit "$PING_STATUS"
fi
if [ "$SHUTDOWN_STATUS" != 0 ]; then
  echo "::error::server did not shut down cleanly after 'stop' on stdin"
  exit 1
fi
if [ "$EXIT_CODE" != 0 ]; then
  echo "::error::server exited with code $EXIT_CODE after 'stop' on stdin, expected 0"
  exit 1
fi
if [ "$RUN_STATUS" != 0 ]; then
  echo "::error::docker run exited $RUN_STATUS after 'stop' on stdin, expected 0"
  exit 1
fi
echo "REACHABLE confirmed on $HOST_PORT/udp"
