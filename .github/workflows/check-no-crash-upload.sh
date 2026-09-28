#!/usr/bin/env bash
# Fails if a server log shows a crash dump upload attempt, successful or not.
# CI boots pass --auto-report.enabled=0, and the shipped pocketmine.yml has
# auto-report on and pointed at a public archive, so any of these lines means
# the flag did not reach the server.
#
# The patterns are the four lines Server::crashDump() can log once it has
# decided to post (src/Server.php, pocketmine.crash.archive in
# resources/translations/eng.ini). pocketmine.crash.submit is left out on
# purpose: it also mentions the Crash Archive but is logged on every crash
# whether reporting is on or off.
#
# Usage: check-no-crash-upload.sh <log file>
set -euo pipefail

LOG="${1:?usage: check-no-crash-upload.sh <log file>}"
if [ ! -f "$LOG" ]; then
  echo "::error::no log at $LOG, so the crash upload check has nothing to read"
  exit 2
fi

HITS="$(grep -nF \
  -e "automatically submitted to the Crash Archive" \
  -e "Automatic crash report submission failed" \
  -e "received from crash archive" \
  -e "Failed to communicate with crash archive" \
  "$LOG" || true)"

if [ -n "$HITS" ]; then
  echo "::error::server attempted a crash archive upload; --auto-report.enabled=0 did not take effect"
  echo "$HITS"
  exit 1
fi
echo "no crash archive upload in $LOG"
