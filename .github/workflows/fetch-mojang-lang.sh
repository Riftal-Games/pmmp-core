#!/usr/bin/env bash
# Downloads Mojang's en_US.lang from $1 to mojang-lang/en_US.lang and writes
# its sha256 to $GITHUB_OUTPUT as sha. A failed download leaves no file and
# no sha, which is what tells main.yml to restore a cached copy instead.
set -euo pipefail

URL="$1"
mkdir -p mojang-lang
rm -f mojang-lang/en_US.lang
if curl -fsSL --connect-timeout 15 --max-time 60 --retry 2 --retry-delay 5 --retry-all-errors -o mojang-lang/en_US.lang "$URL"; then
  echo "sha=$(sha256sum mojang-lang/en_US.lang | cut -d' ' -f1)" >> "$GITHUB_OUTPUT"
else
  rm -f mojang-lang/en_US.lang
  echo "::warning::Could not fetch $URL, verifying against the newest cached copy"
fi
