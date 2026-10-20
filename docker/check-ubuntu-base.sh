#!/usr/bin/env bash
# Walks every `FROM` line in a Dockerfile and prints one line per stage whose
# base image is not $2 (an Ubuntu tag like "24.04") pinned by digest, or
# nothing if all stages pass. Exit status is always 0: the straggler list
# itself is the result, so the caller decides pass/fail on whether it printed
# anything.
#
# An external stage passes only as `ubuntu:<tag>@sha256:<64 lowercase hex>`,
# and every external stage must carry the same digest as the first one. One
# shared digest means the runtime stage's /etc/os-release, which CI reads,
# speaks for the two build stages too.
#
# A stage that chains off an earlier one (`FROM build-pocketmine AS final`)
# names a stage already declared in this file, not an external image, and
# inherits whatever its parent already had to pass. `--platform=...` is a
# flag on the FROM instruction, not part of the image name, and has to be
# stripped before comparing. Extracted out of docker-image-ci.yml so
# check-ubuntu-base.selftest.sh can exercise every branch against fixtures,
# not just whatever docker/Dockerfile happens to contain today.
set -euo pipefail

DOCKERFILE="${1:?usage: check-ubuntu-base.sh <dockerfile> <expected-ubuntu-tag>}"
EXPECTED_UBUNTU="${2:?usage: check-ubuntu-base.sh <dockerfile> <expected-ubuntu-tag>}"

# The digest is matched by length and character class, not by a {64}
# interval, which not every awk supports.
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
    if (!(image in stages)) {
      at = index(image, "@")
      digest = substr(image, at + 1)
      # With no "@", at is 0 and the name before it is empty, never expected.
      if (substr(image, 1, at - 1) != expected ||
          length(digest) != 71 || digest !~ /^sha256:[0-9a-f]+$/) {
        print NR ":" $0
      } else if (shared == "") {
        shared = digest
      } else if (digest != shared) {
        print NR ":" $0
      }
    }
    if (stagename != "") {
      stages[stagename] = 1
    }
  }
' "$DOCKERFILE"
