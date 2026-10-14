#!/usr/bin/env bash
# Fails unless every step of an image workflow that runs or tags the image
# names it by "$IMAGE_ID", the ID the build step reported, and nothing names
# the bare tag but the build's own tags: line and the sha tag's repository.
# Run on docker-image-ci.yml and docker-image-publish.yml.
# The riftal runners share one docker daemon, so the bare tag is whatever
# image any run built last, and a smoke verdict on it may be a verdict on
# someone else's build (#164).
#
# Comments are skipped, whole-line and trailing, so a commented-out line can
# neither satisfy the check nor trip it. Continued lines are joined first.
# Each kind of step must appear at least once, so a renamed script fails here
# rather than passing unchecked. CI tags through tag-image-sha.sh and publish
# through push-pinned-image.sh, so either one, or docker tag, satisfies the
# tag kind.
#
# Any other push fails: it pushes whatever the name points at by then, and
# only push-pinned-image.sh checks that the registry got $IMAGE_ID (#185).
# That is docker push or docker image push, a build or bake with --push or a
# registry output, docker buildx imagetools create, and a push: input other
# than false, as build-push-action takes. Global options and their values
# may sit between docker, or buildx, and the verb (#187).
#
# Usage: check-pinned-image.sh <workflow file>
set -uo pipefail

if [ "$#" != 1 ]; then
  echo "usage: check-pinned-image.sh <workflow file>" >&2
  exit 2
fi
FILE="$1"
if [ ! -f "$FILE" ]; then
  echo "::error::no workflow file at $FILE"
  exit 1
fi

# The literal text a step must pass, never expanded here.
# shellcheck disable=SC2016
PINNED='"$IMAGE_ID"'
TAG_CALL="tag-image-sha.sh local-pocketmine-mp $PINNED"
# VALUE is one shell word, quoted or not. OPTS is any run of options, each
# with an optional value, so DOCKER and BUILDX end just before the verb.
Q="'"
VALUE="(\"[^\"]*\"|${Q}[^${Q}]*${Q}|[^-[:space:];&|][^[:space:];&|]*)"
OPTS="([[:space:]]+-[^[:space:]=]*(=${VALUE})?([[:space:]]+${VALUE})?)*"
DOCKER="docker${OPTS}[[:space:]]+"
BUILDX="${DOCKER}buildx${OPTS}[[:space:]]+"
FAILED=0
PINS=0
RUNS=0
REACHABLE=0
CRASH=0
TAGS=0
RETAGS=0
PUSHES=0

fail() {
  echo "::error file=$FILE,line=$1::$2"
  FAILED=1
}

while IFS=$'\t' read -r NUM CODE; do
  if [[ "$CODE" == *steps.build.outputs.imageid* ]]; then
    PINS=$((PINS + 1))
  fi
  # Outside the chain below, so a run or tag call on the same line cannot hide it.
  if [[ "$CODE" =~ ${DOCKER}(image[[:space:]]+)?push([[:space:]]|$) ]]; then
    fail "$NUM" "a bare docker push sends whatever the name points at by then; push through push-pinned-image.sh $PINNED"
  fi
  if [[ "$CODE" =~ (^|[[:space:]])--push([[:space:]=]|$) ]] || [[ "$CODE" == *push=true* ]] || [[ "$CODE" == *type=registry* ]]; then
    fail "$NUM" "a build that pushes sends whatever it built by name; build with push: false and push through push-pinned-image.sh $PINNED"
  fi
  if [[ "$CODE" =~ ${BUILDX}imagetools[[:space:]]+create([[:space:]]|$) ]]; then
    fail "$NUM" "docker buildx imagetools create pushes a manifest by name; push through push-pinned-image.sh $PINNED"
  fi
  # An empty or flow-mapping push: is the on: trigger, never an action input.
  if [[ "$CODE" =~ ^[[:space:]]*(-[[:space:]]+)?push:[[:space:]]*([^[:space:]{[].*)?$ ]] && [ -n "${BASH_REMATCH[2]}" ]; then
    VAL="${BASH_REMATCH[2]%"${BASH_REMATCH[2]##*[![:space:]]}"}"
    if [ "$VAL" != false ] && [ "$VAL" != '"false"' ] && [ "$VAL" != "'false'" ]; then
      fail "$NUM" "push: $VAL pushes the build by name; build with push: false and push through push-pinned-image.sh $PINNED"
    fi
  fi
  KIND=
  if [[ "$CODE" =~ ${DOCKER}(container[[:space:]]+)?(run|create)([[:space:]]|$) ]]; then
    KIND=run
    RUNS=$((RUNS + 1))
  elif [[ "$CODE" =~ ${DOCKER}(image[[:space:]]+)?tag([[:space:]]|$) ]]; then
    KIND=tag
    RETAGS=$((RETAGS + 1))
  elif [[ "$CODE" == *push-pinned-image.sh* ]]; then
    KIND=push
    PUSHES=$((PUSHES + 1))
  elif [[ "$CODE" == *reachable-smoke.sh* ]]; then
    KIND=reachable
    REACHABLE=$((REACHABLE + 1))
  elif [[ "$CODE" == *crash-boot-smoke.sh* ]]; then
    KIND=crash
    CRASH=$((CRASH + 1))
  elif [[ "$CODE" == *tag-image-sha.sh* ]]; then
    KIND=tag
    TAGS=$((TAGS + 1))
    if [[ "$CODE" != *"$TAG_CALL"* ]]; then
      fail "$NUM" "tag-image-sha.sh must be called as: $TAG_CALL"
    fi
  fi
  if [ -n "$KIND" ] && [[ "$CODE" != *"$PINNED"* ]]; then
    fail "$NUM" "this $KIND step does not name the image by $PINNED"
  fi
  REST="${CODE//"$TAG_CALL"/}"
  if [[ "$REST" == *local-pocketmine-mp* ]] && ! [[ "$CODE" =~ ^[[:space:]]*tags:[[:space:]]*local-pocketmine-mp[[:space:]]*$ ]]; then
    fail "$NUM" "names the bare tag local-pocketmine-mp, which another run can rebuild; use $PINNED"
  fi
done < <(awk '
  {
    sub(/\r$/, "")
    if (cont) {
      line = line " " $0
    } else {
      if ($0 ~ /^[[:space:]]*#/) next
      line = $0
      start = NR
    }
    cont = sub(/\\$/, "", line)
    if (cont) next
    sub(/[[:space:]]#.*$/, "", line)
    if (line ~ /[^[:space:]]/) printf "%d\t%s\n", start, line
  }
' "$FILE")

if [ "$PINS" = 0 ]; then
  fail 1 "no step reads steps.build.outputs.imageid, so nothing pins the image this run built"
fi
for PAIR in "docker run:$RUNS" "reachable-smoke.sh:$REACHABLE" "crash-boot-smoke.sh:$CRASH" "tag-image-sha.sh, docker tag or push-pinned-image.sh:$((TAGS + RETAGS + PUSHES))"; do
  if [ "${PAIR##*:}" = 0 ]; then
    fail 1 "no ${PAIR%:*} call found, so it was never checked"
  fi
done
if [ "$FAILED" = 0 ]; then
  echo "$FILE: $RUNS docker run, $REACHABLE reachable, $CRASH crash, $TAGS tag-image-sha.sh, $RETAGS docker tag and $PUSHES push-pinned-image.sh call(s) name the image by $PINNED"
fi
exit "$FAILED"
