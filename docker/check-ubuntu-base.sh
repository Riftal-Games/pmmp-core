#!/usr/bin/env bash
# Walks every `FROM` line in a Dockerfile and prints one line per stage whose
# base image is not $2 (an Ubuntu tag like "24.04"), or nothing if all stages
# are pinned to it. Exit status is always 0: the straggler list itself is the
# result, so the caller decides pass/fail on whether it printed anything.
#
# A stage that chains off an earlier one (`FROM build-pocketmine AS final`)
# names a stage already declared in this file, not an external image, and
# inherits whatever its parent already had to pass. `--platform=...` is a
# flag on the FROM instruction, not part of the image name, and has to be
# stripped before comparing. Extracted out of docker-image-ci.yml so
# check-ubuntu-base.selftest.sh can exercise both branches against fixtures,
# not just whatever docker/Dockerfile happens to contain today.
set -euo pipefail

DOCKERFILE="${1:?usage: check-ubuntu-base.sh <dockerfile> <expected-ubuntu-tag>}"
EXPECTED_UBUNTU="${2:?usage: check-ubuntu-base.sh <dockerfile> <expected-ubuntu-tag>}"

awk -v expected="ubuntu:${EXPECTED_UBUNTU}" '
  /^FROM / {
    line = $0
    sub(/^FROM[ \t]+/, "", line)
    sub(/^--platform=[^ \t]+[ \t]+/, "", line)
    n = split(line, parts, /[ \t]+/)
    image = parts[1]
    stagename = ""
    for (i = 1; i <= n; i++) {
      if (parts[i] == "AS" || parts[i] == "as") {
        stagename = parts[i + 1]
      }
    }
    if (!(image in stages) && image != expected) {
      print NR ":" $0
    }
    if (stagename != "") {
      stages[stagename] = 1
    }
  }
' "$DOCKERFILE"
