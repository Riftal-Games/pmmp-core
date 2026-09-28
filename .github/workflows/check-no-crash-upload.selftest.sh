#!/usr/bin/env bash
# Runs check-no-crash-upload.sh against fixture logs, so a pattern that no
# longer matches fails here rather than letting every boot step pass quietly.
set -uo pipefail

CHECK="$(dirname "$0")/check-no-crash-upload.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

expect() {
  local want="$1" name="$2" line="$3" got=0
  printf '[12:00:00.000] [Server thread/INFO]: Starting server\n%s\n' "$line" > "$DIR/$name.log"
  bash "$CHECK" "$DIR/$name.log" > /dev/null 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    FAILED=1
  else
    echo "ok   $name"
  fi
}

expect 0 clean-boot '[12:00:01.000] [Server thread/INFO]: Done (1.234s)! For help, type "help" or "?"'
expect 0 crash-without-upload '[12:00:01.000] [Server thread/EMERGENCY]: Please upload the "/data/crashdumps/x.log" file to the Crash Archive and submit the link to the Bug Reporting page. Give as much info as you can.'
expect 1 upload-succeeded '[12:00:01.000] [Server thread/EMERGENCY]: The crash dump has been automatically submitted to the Crash Archive. You can view it on https://example.invalid/view/651 or use the ID #651.'
expect 1 upload-rejected '[12:00:01.000] [Server thread/EMERGENCY]: Automatic crash report submission failed: rate limited'
expect 1 upload-bad-json '[12:00:01.000] [Server thread/EMERGENCY]: Invalid JSON response received from crash archive: <html>'
expect 1 upload-unreachable '[12:00:01.000] [Server thread/EMERGENCY]: Failed to communicate with crash archive: Connection refused'

got=0
bash "$CHECK" "$DIR/missing.log" > /dev/null 2>&1 || got=$?
if [ "$got" != 2 ]; then
  echo "FAIL missing-log: exit $got, expected 2"
  FAILED=1
else
  echo "ok   missing-log"
fi

exit "$FAILED"
