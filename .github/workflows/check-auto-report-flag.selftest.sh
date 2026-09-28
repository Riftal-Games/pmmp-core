#!/usr/bin/env bash
# Runs check-auto-report-flag.sh against fixture workflows, so a check that
# stopped telling a good boot line from a bad one fails here instead of
# passing both workflow files quietly.
set -uo pipefail

CHECK="$(dirname "$0")/check-auto-report-flag.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

expect() {
  local want="$1" name="$2" body="$3" got=0
  printf '%s\n' "$body" > "$DIR/$name.yml"
  bash "$CHECK" "$DIR/$name.yml" > /dev/null 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    FAILED=1
  else
    echo "ok   $name"
  fi
}

GOOD='        echo stop | docker run --rm -i -e POCKETMINE_ARGS="--settings.enable-dev-builds=1 --auto-report.enabled=0" local-pocketmine-mp'
GOOD_MID="$(cat <<'EOF'
          -e POCKETMINE_ARGS="--settings.enable-dev-builds=1 --auto-report.enabled=0 --motd=$EXPECTED_MOTD" \
EOF
)"

expect 0 flag-last "$GOOD"
expect 0 flag-mid "$GOOD_MID"
expect 0 both-forms "$GOOD
$GOOD_MID"
expect 0 comment-ignored "$GOOD
    # POCKETMINE_ARGS=\"--settings.enable-dev-builds=1\""
expect 1 flag-missing '        echo stop | docker run --rm -i -e POCKETMINE_ARGS="--settings.enable-dev-builds=1" local-pocketmine-mp'
expect 1 one-of-two-missing "$GOOD
          -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --motd=\$EXPECTED_MOTD\" \\"
expect 1 flag-doubled '        -e POCKETMINE_ARGS="--auto-report.enabled=0 --auto-report.enabled=0"'
expect 1 flag-false '        -e POCKETMINE_ARGS="--settings.enable-dev-builds=1 --auto-report.enabled=false"'
expect 1 flag-one '        -e POCKETMINE_ARGS="--settings.enable-dev-builds=1 --auto-report.enabled=1"'
expect 1 flag-zero-zero '        -e POCKETMINE_ARGS="--settings.enable-dev-builds=1 --auto-report.enabled=00"'
expect 1 flag-no-value '        -e POCKETMINE_ARGS="--settings.enable-dev-builds=1 --auto-report.enabled"'
expect 1 zero-then-other '        -e POCKETMINE_ARGS="--auto-report.enabled=0 --auto-report.enabled=1"'
expect 1 yaml-env-missing '          POCKETMINE_ARGS: "--settings.enable-dev-builds=1"'
expect 1 no-assignment '        run: echo stop | docker run --rm -i local-pocketmine-mp'

got=0
bash "$CHECK" "$DIR/missing.yml" > /dev/null 2>&1 || got=$?
if [ "$got" != 1 ]; then
  echo "FAIL missing-file: exit $got, expected 1"
  FAILED=1
else
  echo "ok   missing-file"
fi

exit "$FAILED"
