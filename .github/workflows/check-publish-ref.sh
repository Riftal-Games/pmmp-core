#!/usr/bin/env bash
# Fails unless the checked-out HEAD is the commit the given tag names, then
# prints that commit. The publish workflow pushes its image under the tag, so
# a tree that is not the tag's would ship mislabelled (#117). A dispatch runs
# on whatever ref it was started from, which is why the checkout alone is not
# trusted to have landed on the tag.
#
# Usage: check-publish-ref.sh <tag>
set -uo pipefail

if [ "$#" != 1 ] || [ -z "$1" ]; then
  echo "usage: check-publish-ref.sh <tag>" >&2
  exit 2
fi
TAG="$1"

if ! TAGGED="$(git rev-parse --verify --quiet "refs/tags/$TAG^{commit}")"; then
  echo "::error::no tag $TAG in the checked-out repository, so nothing proves what is being published" >&2
  exit 1
fi
if ! HEAD="$(git rev-parse --verify --quiet "HEAD^{commit}")"; then
  echo "::error::no HEAD commit checked out" >&2
  exit 1
fi
if [ "$HEAD" != "$TAGGED" ]; then
  echo "::error::checked out $HEAD, but tag $TAG is $TAGGED; refusing to publish one tree under another's tag" >&2
  exit 1
fi
printf '%s\n' "$HEAD"
