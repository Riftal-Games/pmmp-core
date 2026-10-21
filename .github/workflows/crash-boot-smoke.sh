#!/usr/bin/env bash
# Crash-on-boot check shared by docker-image-ci.yml and docker-image-publish.yml.
# Boots the image detached, so with no stdin, and with a plugin that starts a
# never-ending thread and then throws in onEnable, and expects the container to
# exit non-zero on its own, with no `stop` and no `docker stop`.
# Server::crashDump() sleeps until the server has 120s of uptime before it
# exits, so the limit sits above that.
#
# Usage: crash-boot-smoke.sh <image> <container name> <plugins dir>
set -euo pipefail

if [ "$#" != 3 ]; then
  echo "usage: crash-boot-smoke.sh <image> <container name> <plugins dir>" >&2
  exit 2
fi
IMAGE="$1"
CONTAINER_NAME="$2"
PLUGINS="$3"
LIMIT="${CRASH_EXIT_LIMIT:-180}"

HERE="$(dirname "$0")"
LOG="$(mktemp)"

cleanup() {
  local status=$?
  docker stop "$CONTAINER_NAME" > /dev/null 2>&1 || true
  docker rm -v "$CONTAINER_NAME" > /dev/null 2>&1 || true
  rm -f "$LOG"
  exit "$status"
}
trap cleanup EXIT

# --auto-report.enabled=0 exactly once: this boot crashes on purpose, and the
# shipped pocketmine.yml posts crash dumps to a public archive (#91).
# Should the flag stop taking effect, the post goes to a closed port on a
# container with no network, so no dump leaves the runner and the refused
# connection logs a line check-no-crash-upload.sh fails on (#95).
# --auto-updater.enabled=0 exactly once as well: with no network the update
# check cannot leave either, but one rule then covers every CI boot (#96).
docker run -d --name "$CONTAINER_NAME" \
  --network none \
  -v "$PLUGINS:/plugins" \
  -e POCKETMINE_ARGS="--settings.enable-dev-builds=1 --auto-report.enabled=0 --auto-updater.enabled=0 --auto-report.host=127.0.0.1:9" \
  "$IMAGE" > /dev/null

# Waiting on `docker wait` rather than an attached `docker run`: the attached
# client outlives a SIGTERM from `timeout` while the container is still up.
# `docker wait` prints the container's exit code and exits 0 itself.
WAIT_STATUS=0
EXIT_CODE=$(timeout "$LIMIT" docker wait "$CONTAINER_NAME") || WAIT_STATUS=$?
docker logs "$CONTAINER_NAME" > "$LOG" 2>&1 || true

echo "--- server log ---"
cat "$LOG"
echo "--- end server log ---"
"$HERE/check-no-crash-upload.sh" "$LOG"

# pocketmine.crash.create in resources/translations/eng.ini. Without it the
# fixture never reached onEnable and nothing below says anything about a crash.
if ! grep -qF "the server has crashed" "$LOG"; then
  echo "::error::the server never logged a crash, so the crash exit path was not exercised"
  exit 1
fi
if [ "$WAIT_STATUS" != 0 ]; then
  echo "::error::server was still running ${LIMIT}s after crashing on boot"
  exit 1
fi
if [ "$EXIT_CODE" = 0 ]; then
  echo "::error::server exited 0 after crashing on boot, expected non-zero"
  exit 1
fi
echo "crashed server exited $EXIT_CODE on its own"
