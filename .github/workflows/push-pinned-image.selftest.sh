#!/usr/bin/env bash
# Runs push-pinned-image.sh against a stub `docker`, so a push the registry
# holds as this run's image ID is proven to pass, under either image store,
# and a push of anything else, as when another run retags the name between
# the tag and the push, is proven to fail. The publish workflow only ever
# pushes on a release, so nothing else exercises the script before then.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/push-pinned-image.sh"
WORKFLOW="$HERE/docker-image-publish.yml"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0
ID=sha256:feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface
DIGEST=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
OTHER=sha256:89abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567
REPOSITORY=ghcr.io/riftal-games/pmmp-core
IMAGE="$REPOSITORY:5.49.1"

mkdir "$DIR/bin"
cat > "$DIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB_CALLS"
case "$1" in
  tag) ;;
  push)
    echo "The push refers to repository [${2%:*}]"
    printf '%s' "${STUB_PUSH_OUT-}"
    exit "${STUB_PUSH_STATUS:-0}"
    ;;
  buildx)
    [ "$2 $3 $4" = "imagetools inspect --raw" ] || { echo "stub docker: unexpected call: $*" >&2; exit 125; }
    printf '%s\n' "$STUB_MANIFEST"
    ;;
  *) echo "stub docker: unexpected call: $*" >&2; exit 125 ;;
esac
EOF
chmod +x "$DIR/bin/docker"

manifest() {
  printf '{"schemaVersion":2,"mediaType":"application/vnd.docker.distribution.manifest.v2+json","config":{"mediaType":"application/vnd.docker.container.image.v1+json","size":7023,"digest":"%s"},"layers":[]}' "$1"
}

# expect <exit status> <case name> <text the output must contain> [VAR=value...]
# ARGS, when set, replaces the image ID and name the workflow passes.
expect() {
  local want="$1" name="$2" text="$3" got=0
  shift 3
  mkdir "$DIR/$name"
  : > "$DIR/$name/calls"
  # The default ARGS is two words, split on purpose.
  # shellcheck disable=SC2086
  env PATH="$DIR/bin:$PATH" STUB_CALLS="$DIR/$name/calls" \
    STUB_PUSH_OUT="5.49.1: digest: $DIGEST size: 2758"$'\n' STUB_MANIFEST="$(manifest "$ID")" "$@" \
    bash "$SCRIPT" ${ARGS-$ID $IMAGE} > "$DIR/$name/out" 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
  elif ! grep -qF -- "$text" "$DIR/$name/out"; then
    echo "FAIL $name: output lacks: $text"
  elif grep -q '^buildx' "$DIR/$name/calls" && ! grep -qxF "buildx imagetools inspect --raw $REPOSITORY@$DIGEST" "$DIR/$name/calls"; then
    echo "FAIL $name: read the registry by something other than the pushed digest"
  else
    echo "ok   $name"
    return
  fi
  FAILED=1
  cat "$DIR/$name/out" "$DIR/$name/calls"
}

expect 0 classic-store "pushed $ID as $IMAGE, digest $DIGEST"
expect 0 containerd-store "pushed $ID as $IMAGE, digest $ID" STUB_PUSH_OUT="5.49.1: digest: $ID size: 2758"$'\n' STUB_MANIFEST=unreadable
expect 0 digest-repeated "digest $DIGEST" STUB_PUSH_OUT="5.49.1: digest: $DIGEST size: 2758"$'\n'"5.49.1: digest: $DIGEST size: 2758"$'\n'
expect 1 retagged-before-push "not the $ID this run built" STUB_MANIFEST="$(manifest "$OTHER")"
expect 1 index-pushed "whose config is ''" STUB_MANIFEST='{"schemaVersion":2,"manifests":[]}'
expect 1 no-digest "reported 0 digest(s)" STUB_PUSH_OUT=
expect 1 short-digest "reported 0 digest(s)" STUB_PUSH_OUT="5.49.1: digest: sha256:0123 size: 2758"$'\n'
expect 1 two-digests "reported 2 digest(s)" STUB_PUSH_OUT="5.49.1: digest: $DIGEST size: 2758"$'\n'"5.49.1: digest: $OTHER size: 2758"$'\n'
expect 1 push-fails "The push refers to repository" STUB_PUSH_STATUS=1
ARGS="local-pocketmine-mp $IMAGE" expect 1 bare-tag-for-id "is not a sha256 image ID"
ARGS="sha256:feedface $IMAGE" expect 1 short-id "is not a sha256 image ID"
ARGS="$ID $REPOSITORY" expect 1 no-tag "carries no tag"
ARGS="$ID localhost:5000/pmmp-core" expect 1 port-but-no-tag "carries no tag"
ARGS="$ID $REPOSITORY:" expect 1 empty-tag "carries no tag"

if ! grep -qxF "tag $ID $IMAGE" "$DIR/classic-store/calls" || ! grep -qxF "push $IMAGE" "$DIR/classic-store/calls"; then
  echo "FAIL tag-then-push: did not tag $ID as $IMAGE and push $IMAGE"
  cat "$DIR/classic-store/calls"
  FAILED=1
else
  echo "ok   tag-then-push"
fi

got=0
bash "$SCRIPT" "$ID" > "$DIR/one-arg.out" 2>&1 || got=$?
if [ "$got" != 2 ]; then
  echo "FAIL one-arg: exit $got, expected 2"
  FAILED=1
else
  echo "ok   one-arg"
fi

# The workflow's own text, matched verbatim, so none of it may expand.
# shellcheck disable=SC2016
CALLS="$(tr -d '\r' < "$WORKFLOW" | grep -cxF '        run: .github/workflows/push-pinned-image.sh "$IMAGE_ID" "$IMAGE"')"
STEPS="$(grep -cE '^      - name: Push ' "$WORKFLOW")"
if [ "$STEPS" = 0 ] || [ "$CALLS" != "$STEPS" ]; then
  echo "FAIL workflow-wired: $CALLS of $STEPS push step(s) in docker-image-publish.yml run push-pinned-image.sh"
  FAILED=1
else
  echo "ok   workflow-wired"
fi

exit "$FAILED"
