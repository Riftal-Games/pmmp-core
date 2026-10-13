#!/usr/bin/env bash
# Tags the image this run built as <name> and pushes it, then fails unless
# the registry holds that image ID under the digest the push reported.
#
# The push goes by name, and a daemon shared with other runs, as the
# self-hosted runners have, lets another run retag the name between the tag
# and the push. Checking the registry's copy against the image ID detects a
# push that went out under the wrong image. The digest is read from this
# push's own output, never from the tag, which a later push may already have
# moved.
#
# The classic image store's ID is the config digest of the manifest it
# pushes. The containerd store's ID is the digest it pushes. Anything else
# fails rather than guessing which image went out.
#
# Usage: push-pinned-image.sh <image id> <name>:<tag>
set -euo pipefail

if [ "$#" != 2 ]; then
  echo "usage: push-pinned-image.sh <image id> <name>:<tag>" >&2
  exit 2
fi
ID="$1"
IMAGE="$2"

if ! [[ "$ID" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "::error::'$ID' is not a sha256 image ID, so it cannot pin the image this run built"
  exit 1
fi
if ! [[ "${IMAGE##*/}" == *:?* ]]; then
  echo "::error::'$IMAGE' carries no tag to push"
  exit 1
fi
REPOSITORY="${IMAGE%:*}"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

docker tag "$ID" "$IMAGE"
docker push "$IMAGE" | tee "$LOG"

mapfile -t DIGESTS < <(sed -n 's/^.*: digest: \(sha256:[0-9a-f]\{64\}\) size: [0-9]*$/\1/p' "$LOG" | sort -u)
if [ "${#DIGESTS[@]}" != 1 ]; then
  echo "::error::the push of $IMAGE reported ${#DIGESTS[@]} digest(s), so which image went out is unknown"
  exit 1
fi
DIGEST="${DIGESTS[0]}"

if [ "$DIGEST" = "$ID" ]; then
  echo "pushed $ID as $IMAGE, digest $DIGEST"
  exit 0
fi

CONFIG="$(docker buildx imagetools inspect --raw "$REPOSITORY@$DIGEST" | jq -r '.config.digest // empty')"
if [ "$CONFIG" != "$ID" ]; then
  echo "::error::$IMAGE was pushed as $DIGEST, whose config is '$CONFIG', not the $ID this run built; another run may have retagged $IMAGE before the push, so the image now under it is not this run's"
  exit 1
fi
echo "pushed $ID as $IMAGE, digest $DIGEST"
