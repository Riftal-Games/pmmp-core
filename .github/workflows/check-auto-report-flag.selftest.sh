#!/usr/bin/env bash
# Runs check-auto-report-flag.sh against fixture workflows, so a check that
# stopped telling a good boot line from a bad one fails here instead of
# passing both workflow files quietly.
# A fixture that names a flag must fail with one error, on that flag, so a
# bad auto-report value cannot pass only because the updater flag is wrong.
set -uo pipefail

CHECK="$(dirname "$0")/check-auto-report-flag.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

expect() {
  local want="$1" name="$2" body="$3" flag="${4:-}" got=0 out errors
  printf '%s\n' "$body" > "$DIR/$name.yml"
  out="$(bash "$CHECK" "$DIR/$name.yml" 2>&1)" || got=$?
  errors="$(grep -c '^::error' <<< "$out")"
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    FAILED=1
  elif [ -n "$flag" ] && { [ "$errors" != 1 ] || ! grep -qF -- "must pass --$flag=0 exactly once" <<< "$out"; }; then
    echo "FAIL $name: expected one error on --$flag, got:"
    echo "$out"
    FAILED=1
  else
    echo "ok   $name"
  fi
}

R=auto-report.enabled
U=auto-updater.enabled
GOOD="        echo stop | docker run --rm -i -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$R=0 --$U=0\" local-pocketmine-mp"
GOOD_MID="$(cat <<'EOF'
          -e POCKETMINE_ARGS="--settings.enable-dev-builds=1 --auto-report.enabled=0 --auto-updater.enabled=0 --motd=$EXPECTED_MOTD" \
EOF
)"

expect 0 flag-last "$GOOD"
expect 0 flag-mid "$GOOD_MID"
expect 0 both-forms "$GOOD
$GOOD_MID"
expect 0 comment-ignored "$GOOD
    # POCKETMINE_ARGS=\"--settings.enable-dev-builds=1\""
expect 0 updater-first "        -e POCKETMINE_ARGS=\"--$U=0 --$R=0\""
expect 1 both-missing '        echo stop | docker run --rm -i -e POCKETMINE_ARGS="--settings.enable-dev-builds=1" local-pocketmine-mp'
expect 1 one-of-two-missing "$GOOD
          -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --motd=\$EXPECTED_MOTD\" \\"

expect 1 flag-missing "        -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$U=0\"" "$R"
expect 1 flag-doubled "        -e POCKETMINE_ARGS=\"--$R=0 --$R=0 --$U=0\"" "$R"
expect 1 flag-false "        -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$R=false --$U=0\"" "$R"
expect 1 flag-one "        -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$R=1 --$U=0\"" "$R"
expect 1 flag-zero-zero "        -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$R=00 --$U=0\"" "$R"
expect 1 flag-no-value "        -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$U=0 --$R\"" "$R"
expect 1 zero-then-other "        -e POCKETMINE_ARGS=\"--$R=0 --$R=1 --$U=0\"" "$R"

expect 1 updater-missing "        -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$R=0\"" "$U"
expect 1 updater-doubled "        -e POCKETMINE_ARGS=\"--$R=0 --$U=0 --$U=0\"" "$U"
expect 1 updater-false "        -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$R=0 --$U=false\"" "$U"
expect 1 updater-one "        -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$R=0 --$U=1\"" "$U"
expect 1 updater-zero-zero "        -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$R=0 --$U=00\"" "$U"
expect 1 updater-no-value "        -e POCKETMINE_ARGS=\"--settings.enable-dev-builds=1 --$R=0 --$U\"" "$U"
expect 1 updater-zero-then-other "        -e POCKETMINE_ARGS=\"--$R=0 --$U=0 --$U=1\"" "$U"

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
