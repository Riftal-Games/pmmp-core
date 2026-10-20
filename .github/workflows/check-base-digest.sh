#!/usr/bin/env bash
# Compares the ubuntu:24.04 index digest a Dockerfile pins with the one the
# registry serves for the tag today. Exits 0 when they match, 1 when the tag
# has moved on, and 2 when either digest cannot be read: an unresolvable
# digest is an error, never a pass. On drift it writes pinned= and current=
# to $GITHUB_OUTPUT for the step that files the refresh issue.
#
# RESOLVE_CMD replaces the registry lookup, so check-base-digest.selftest.sh
# can drive every outcome without the network.
#
# Usage: check-base-digest.sh <dockerfile>
set -uo pipefail

DOCKERFILE="${1:?usage: check-base-digest.sh <dockerfile>}"
TAG="ubuntu:24.04"
DIGEST_RE='^sha256:[0-9a-f]{64}$'

# The index digest, not a single platform's manifest, is what the FROM lines
# pin, and it is the digest the top-level manifest of imagetools reports.
resolve() {
  if [ -n "${RESOLVE_CMD:-}" ]; then
    bash -c "$RESOLVE_CMD"
  else
    timeout 120 docker buildx imagetools inspect --format '{{json .Manifest}}' "$TAG" | jq -r .digest
  fi
}

PINNED="$(grep -E '^FROM ' "$DOCKERFILE" | grep -oE "${TAG//./\\.}@sha256:[0-9a-f]{64}" | sed 's/^.*@//' | sort -u)"
if [ -z "$PINNED" ] || [ "$(wc -l <<< "$PINNED")" -ne 1 ]; then
  echo "::error::$DOCKERFILE does not pin $TAG to exactly one digest, found: ${PINNED:-none}"
  exit 2
fi

if ! CURRENT="$(resolve)"; then
  echo "::error::could not resolve the current digest of $TAG"
  exit 2
fi
if ! [[ "$CURRENT" =~ $DIGEST_RE ]]; then
  echo "::error::the lookup for $TAG returned '$CURRENT', not a sha256 digest"
  exit 2
fi

if [ "$CURRENT" = "$PINNED" ]; then
  echo "$TAG is still $PINNED"
  exit 0
fi
echo "::error::$TAG is now $CURRENT, and $DOCKERFILE pins $PINNED"
{
  echo "pinned=$PINNED"
  echo "current=$CURRENT"
} >> "${GITHUB_OUTPUT:-/dev/null}"
exit 1
