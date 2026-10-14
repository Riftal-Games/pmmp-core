#!/usr/bin/env bash
# Fixtures are workflow text, so "$IMAGE_ID" in single quotes is meant literally.
# shellcheck disable=SC2016
#
# Runs check-pinned-image.sh against docker-image-ci.yml and
# docker-image-publish.yml themselves and against copies of each with one
# "$IMAGE_ID" at a time put back to the bare tag, so every step that runs or
# tags the image, including one added later, is proven to fail the check
# when it stops naming the pinned ID. Fixtures cover the comment and
# continuation handling the real file does not exercise.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-pinned-image.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0
PINNED='"$IMAGE_ID"'

# expect <exit status> <case name> <fixture file>
expect() {
  local want="$1" name="$2" file="$3" got=0
  bash "$CHECK" "$file" > "$DIR/$name.out" 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    cat "$DIR/$name.out"
    FAILED=1
  else
    echo "ok   $name"
  fi
}

# fixture <case name> <body>: a minimal workflow that passes, plus the body.
fixture() {
  cat > "$DIR/$1.yml" <<'EOF'
jobs:
  build:
    steps:
    - id: build
      uses: docker/build-push-action@v7.3.0
      with:
        tags: local-pocketmine-mp
    - env:
        BUILT_ID: ${{ steps.build.outputs.imageid }}
      run: echo "IMAGE_ID=$BUILT_ID" >> "$GITHUB_ENV"
    - run: |
        docker run --rm "$IMAGE_ID" true
        .github/workflows/reachable-smoke.sh "$IMAGE_ID" name 20000 motd
        .github/workflows/crash-boot-smoke.sh "$IMAGE_ID" name ./plugins
        bash .github/workflows/tag-image-sha.sh local-pocketmine-mp "$IMAGE_ID"
EOF
  printf '%s\n' "$2" >> "$DIR/$1.yml"
}

# <workflow name>:<fewest pinned lines>. Publish pins four docker run calls,
# the two smoke scripts and four push-pinned-image.sh calls.
for PAIR in docker-image-ci:7 docker-image-publish:10; do
  NAME="${PAIR%:*}"
  WORKFLOW="$HERE/$NAME.yml"
  expect 0 "$NAME" "$WORKFLOW"

  tr -d '\r' < "$WORKFLOW" | sed 's/$/\r/' > "$DIR/$NAME-crlf.yml"
  expect 0 "$NAME-crlf" "$DIR/$NAME-crlf.yml"

  # Every "$IMAGE_ID" on a line that is not a comment, reverted one at a time.
  mapfile -t LINES < <(grep -nF -- "$PINNED" "$WORKFLOW" | grep -vE '^[0-9]+:[[:space:]]*#' | cut -d: -f1)
  if [ "${#LINES[@]}" -lt "${PAIR##*:}" ]; then
    echo "FAIL reverts: found ${#LINES[@]} pinned line(s) in $NAME.yml, expected at least ${PAIR##*:}"
    FAILED=1
  fi
  for LINE in "${LINES[@]}"; do
    awk -v n="$LINE" -v p="$PINNED" 'NR == n { i = index($0, p); $0 = substr($0, 1, i - 1) "local-pocketmine-mp" substr($0, i + length(p)) } { print }' \
      "$WORKFLOW" > "$DIR/$NAME-revert-$LINE.yml"
    expect 1 "$NAME-revert-line-$LINE" "$DIR/$NAME-revert-$LINE.yml"
  done
done

fixture minimal ''
expect 0 minimal "$DIR/minimal.yml"

fixture comments-mention-bare-tag '    # docker run --rm local-pocketmine-mp true
        # docker run --rm local-pocketmine-mp is what another run rebuilds'
expect 0 comments-mention-bare-tag "$DIR/comments-mention-bare-tag.yml"

fixture bare-run '    - run: docker run --rm local-pocketmine-mp true'
expect 1 bare-run "$DIR/bare-run.yml"

fixture bare-under-commented-pin '    - run: |
        # docker run --rm "$IMAGE_ID" true
        docker run --rm local-pocketmine-mp true'
expect 1 bare-under-commented-pin "$DIR/bare-under-commented-pin.yml"

# Names neither the pin nor the bare tag outside the comment, so only the
# trailing-comment strip can fail it.
fixture pin-only-in-trailing-comment '    - run: docker run --rm "$IMAGE" true # "$IMAGE_ID"'
expect 1 pin-only-in-trailing-comment "$DIR/pin-only-in-trailing-comment.yml"

# A comment line ending in a backslash must not swallow the next real line.
fixture continued-comment-over-bare-run '    - run: |
        # docker run --rm "$IMAGE_ID" true \
        docker run --rm local-pocketmine-mp true'
expect 1 continued-comment-over-bare-run "$DIR/continued-comment-over-bare-run.yml"

fixture pin-in-env-bare-image '    - run: docker run --rm -e ID="$IMAGE_ID" local-pocketmine-mp true'
expect 1 pin-in-env-bare-image "$DIR/pin-in-env-bare-image.yml"

fixture bare-tag-on-continued-line '    - run: |
        docker run --rm \
          local-pocketmine-mp true'
expect 1 bare-tag-on-continued-line "$DIR/bare-tag-on-continued-line.yml"

fixture pin-on-continued-line '    - run: |
        docker run --rm \
          "$IMAGE_ID" true'
expect 0 pin-on-continued-line "$DIR/pin-on-continued-line.yml"

fixture container-run '    - run: docker container run --rm local-pocketmine-mp true'
expect 1 container-run "$DIR/container-run.yml"

fixture tag-through-variable '    - run: IMAGE=local-pocketmine-mp; docker run --rm "$IMAGE_ID" true'
expect 1 tag-through-variable "$DIR/tag-through-variable.yml"

# Names neither the pin nor the bare tag, so only the missing pin can fail it.
fixture run-without-pin '    - run: docker run --rm "$IMAGE" true'
expect 1 run-without-pin "$DIR/run-without-pin.yml"

fixture reachable-without-pin '    - run: .github/workflows/reachable-smoke.sh "$IMAGE" name 20000 motd'
expect 1 reachable-without-pin "$DIR/reachable-without-pin.yml"

fixture crash-without-pin '    - run: .github/workflows/crash-boot-smoke.sh "$IMAGE" name ./plugins'
expect 1 crash-without-pin "$DIR/crash-without-pin.yml"

fixture bare-latest '    - run: .github/workflows/reachable-smoke.sh local-pocketmine-mp:latest name 20000 motd'
expect 1 bare-latest "$DIR/bare-latest.yml"

grep -vF 'steps.build.outputs.imageid' "$DIR/minimal.yml" > "$DIR/no-pin.yml"
expect 1 no-pin "$DIR/no-pin.yml"

grep -vF 'reachable-smoke.sh' "$DIR/minimal.yml" > "$DIR/no-reachable.yml"
expect 1 no-reachable "$DIR/no-reachable.yml"

grep -vF 'tag-image-sha.sh' "$DIR/minimal.yml" > "$DIR/no-tag-call.yml"
expect 1 no-tag-call "$DIR/no-tag-call.yml"

sed 's|tag-image-sha.sh local-pocketmine-mp "$IMAGE_ID"|tag-image-sha.sh "$IMAGE_ID"|' "$DIR/minimal.yml" > "$DIR/tag-without-repository.yml"
expect 1 tag-without-repository "$DIR/tag-without-repository.yml"

# A docker tag in place of tag-image-sha.sh satisfies the tag kind.
sed 's|bash .github/workflows/tag-image-sha.sh local-pocketmine-mp "$IMAGE_ID"|docker tag "$IMAGE_ID" "$IMAGE"|' "$DIR/minimal.yml" > "$DIR/docker-tag-only.yml"
expect 0 docker-tag-only "$DIR/docker-tag-only.yml"

fixture bare-docker-tag '    - run: docker tag local-pocketmine-mp "$IMAGE"'
expect 1 bare-docker-tag "$DIR/bare-docker-tag.yml"

fixture bare-docker-image-tag '    - run: docker image tag local-pocketmine-mp "$IMAGE"'
expect 1 bare-docker-image-tag "$DIR/bare-docker-image-tag.yml"

# Names neither the pin nor the bare tag, so only the missing pin can fail it.
fixture docker-tag-without-pin '    - run: docker tag "$SOURCE" "$IMAGE"'
expect 1 docker-tag-without-pin "$DIR/docker-tag-without-pin.yml"

sed 's|bash .github/workflows/tag-image-sha.sh local-pocketmine-mp "$IMAGE_ID"|.github/workflows/push-pinned-image.sh "$IMAGE_ID" "$IMAGE"|' "$DIR/minimal.yml" > "$DIR/push-script-only.yml"
expect 0 push-script-only "$DIR/push-script-only.yml"

# Names neither the pin nor the bare tag, so only the missing pin can fail it.
fixture push-script-without-pin '    - run: .github/workflows/push-pinned-image.sh "$SOURCE" "$IMAGE"'
expect 1 push-script-without-pin "$DIR/push-script-without-pin.yml"

# Each names the pin, so only the bare push rule can fail it.
fixture docker-push-after-pinned-tag '    - run: |
        docker tag "$IMAGE_ID" "$IMAGE"
        docker push "$IMAGE"'
expect 1 docker-push-after-pinned-tag "$DIR/docker-push-after-pinned-tag.yml"

fixture docker-image-push '    - run: echo "$IMAGE_ID"; docker image push "$IMAGE"'
expect 1 docker-image-push "$DIR/docker-image-push.yml"

fixture docker-push-at-line-end '    - run: echo "$IMAGE_ID" && docker push'
expect 1 docker-push-at-line-end "$DIR/docker-push-at-line-end.yml"

# A run or tag call earlier on the line must not hide the push after it.
fixture docker-push-and-tag-one-line '    - run: docker tag "$IMAGE_ID" "$IMAGE" && docker push "$IMAGE"'
expect 1 docker-push-and-tag-one-line "$DIR/docker-push-and-tag-one-line.yml"

fixture docker-push-semicolon-tag-one-line '    - run: docker tag "$IMAGE_ID" "$IMAGE"; docker push "$IMAGE"'
expect 1 docker-push-semicolon-tag-one-line "$DIR/docker-push-semicolon-tag-one-line.yml"

fixture docker-push-after-run-one-line '    - run: docker run --rm "$IMAGE_ID" true && docker push "$IMAGE"'
expect 1 docker-push-after-run-one-line "$DIR/docker-push-after-run-one-line.yml"

fixture comment-mentions-docker-push '    # docker push "$IMAGE" sends whatever the name points at'
expect 0 comment-mentions-docker-push "$DIR/comment-mentions-docker-push.yml"

# Each names the pin, so only a push rule can fail it. Global options and
# their values sit between docker and the verb (#187).
fixture docker-push-global-option '    - run: echo "$IMAGE_ID"; docker --config "$HOME/.docker" push "$IMAGE"'
expect 1 docker-push-global-option "$DIR/docker-push-global-option.yml"

fixture docker-push-global-option-equals '    - run: echo "$IMAGE_ID"; docker --config="$HOME/my dir" image push "$IMAGE"'
expect 1 docker-push-global-option-equals "$DIR/docker-push-global-option-equals.yml"

fixture docker-push-global-quoted-value '    - run: echo "$IMAGE_ID"; docker --config "$HOME/my dir" push "$IMAGE"'
expect 1 docker-push-global-quoted-value "$DIR/docker-push-global-quoted-value.yml"

fixture docker-push-global-options '    - run: echo "$IMAGE_ID"; docker -H unix:///var/run/docker.sock --debug -l info push "$IMAGE"'
expect 1 docker-push-global-options "$DIR/docker-push-global-options.yml"

fixture docker-push-global-option-continued '    - run: |
        echo "$IMAGE_ID"
        docker --context default \
          push "$IMAGE"'
expect 1 docker-push-global-option-continued "$DIR/docker-push-global-option-continued.yml"

fixture buildx-build-push '    - run: echo "$IMAGE_ID"; docker buildx build --push -t "$IMAGE" .'
expect 1 buildx-build-push "$DIR/buildx-build-push.yml"

fixture docker-build-push '    - run: echo "$IMAGE_ID"; docker build -t "$IMAGE" --push=true .'
expect 1 docker-build-push "$DIR/docker-build-push.yml"

fixture buildx-bake-push '    - run: echo "$IMAGE_ID"; docker buildx bake --push'
expect 1 buildx-bake-push "$DIR/buildx-bake-push.yml"

fixture buildx-output-registry '    - run: echo "$IMAGE_ID"; docker buildx build --output type=registry,name="$IMAGE" .'
expect 1 buildx-output-registry "$DIR/buildx-output-registry.yml"

fixture buildx-output-push-true '    - run: echo "$IMAGE_ID"; docker buildx build -o type=image,name="$IMAGE",push=true .'
expect 1 buildx-output-push-true "$DIR/buildx-output-push-true.yml"

# Buildkit reads push= with Go's strconv.ParseBool, and an empty value as
# true, so every one of these pushes (#212).
for PAIR in True:True TRUE:TRUE one:1 t:t T:T empty: quoted:'"true"'; do
  NAME="buildx-output-push-${PAIR%%:*}"
  fixture "$NAME" "    - run: echo \"\$IMAGE_ID\"; docker buildx build -o type=image,name=\"\$IMAGE\",push=${PAIR#*:} ."
  expect 1 "$NAME" "$DIR/$NAME.yml"
done

fixture buildx-output-push-1-mid-list '    - run: echo "$IMAGE_ID"; docker buildx build -o type=image,push=1,name="$IMAGE" .'
expect 1 buildx-output-push-1-mid-list "$DIR/buildx-output-push-1-mid-list.yml"

fixture buildx-output-push-false '    - run: docker buildx build -o type=image,name="$IMAGE",push=false .'
expect 0 buildx-output-push-false "$DIR/buildx-output-push-false.yml"

fixture buildx-output-push-0 '    - run: docker buildx build -o type=image,name="$IMAGE",push=0 .'
expect 0 buildx-output-push-0 "$DIR/buildx-output-push-0.yml"

# A quoted value is its unquoted value, and push= is a key only inside an
# output value, never the tail of an environment variable's name.
fixture buildx-output-push-quoted-false '    - run: docker buildx build -o type=image,name="$IMAGE",push="false" .'
expect 0 buildx-output-push-quoted-false "$DIR/buildx-output-push-quoted-false.yml"

fixture buildx-output-push-quoted-0 "    - run: docker buildx build -o type=image,name=\"\$IMAGE\",push='0' ."
expect 0 buildx-output-push-quoted-0 "$DIR/buildx-output-push-quoted-0.yml"

for PAIR in no-push-1:NO_PUSH=1 no-push-true:NO_PUSH=true push-empty:PUSH=; do
  NAME="env-${PAIR%%:*}"
  fixture "$NAME" "    - run: ${PAIR#*:} make"
  expect 0 "$NAME" "$DIR/$NAME.yml"
done

fixture buildx-output-quoted-word-push-1 '    - run: echo "$IMAGE_ID"; docker buildx build -o "type=image,name=$IMAGE,push=1" .'
expect 1 buildx-output-quoted-word-push-1 "$DIR/buildx-output-quoted-word-push-1.yml"

fixture buildx-output-push-first '    - run: echo "$IMAGE_ID"; docker buildx build -o push=1,type=image .'
expect 1 buildx-output-push-first "$DIR/buildx-output-push-first.yml"

fixture bake-set-output-push-empty "    - run: echo \"\$IMAGE_ID\"; docker buildx bake --set '*.output=push='"
expect 1 bake-set-output-push-empty "$DIR/bake-set-output-push-empty.yml"

fixture compose-push '    - run: echo "$IMAGE_ID"; docker compose push'
expect 1 compose-push "$DIR/compose-push.yml"

fixture compose-push-options '    - run: echo "$IMAGE_ID"; docker --context default compose -f compose.yml push app'
expect 1 compose-push-options "$DIR/compose-push-options.yml"

fixture docker-compose-push '    - run: echo "$IMAGE_ID"; docker-compose push app'
expect 1 docker-compose-push "$DIR/docker-compose-push.yml"

fixture compose-pull '    - run: docker compose pull'
expect 0 compose-pull "$DIR/compose-pull.yml"

fixture imagetools-create '    - run: echo "$IMAGE_ID"; docker buildx imagetools create -t "$IMAGE" "$SOURCE"'
expect 1 imagetools-create "$DIR/imagetools-create.yml"

fixture imagetools-create-global-options '    - run: echo "$IMAGE_ID"; docker --context default buildx --builder "$B" imagetools create -t "$IMAGE" "$SOURCE"'
expect 1 imagetools-create-global-options "$DIR/imagetools-create-global-options.yml"

fixture build-push-action-push-true '    - uses: docker/build-push-action@v7.3.0
      with:
        tags: ${{ env.IMAGE }}
        push: true'
expect 1 build-push-action-push-true "$DIR/build-push-action-push-true.yml"

fixture build-push-action-push-quoted '    - uses: docker/build-push-action@v7.3.0
      with:
        push: "true"'
expect 1 build-push-action-push-quoted "$DIR/build-push-action-push-quoted.yml"

fixture build-push-action-push-expression '    - uses: docker/build-push-action@v7.3.0
      with:
        push: ${{ github.event_name == '"'push'"' }}'
expect 1 build-push-action-push-expression "$DIR/build-push-action-push-expression.yml"

fixture build-push-action-outputs-registry '    - uses: docker/build-push-action@v7.3.0
      with:
        outputs: type=registry'
expect 1 build-push-action-outputs-registry "$DIR/build-push-action-outputs-registry.yml"

fixture build-push-action-push-false '    - uses: docker/build-push-action@v7.3.0
      with:
        push: false
        load: true'
expect 0 build-push-action-push-false "$DIR/build-push-action-push-false.yml"

fixture push-trigger-key 'on:
  push:
    branches: [riftal]
  pull_request: {}'
expect 0 push-trigger-key "$DIR/push-trigger-key.yml"

fixture push-trigger-flow-mapping 'on:
  push: {branches: [riftal]}'
expect 0 push-trigger-flow-mapping "$DIR/push-trigger-flow-mapping.yml"

fixture imagetools-inspect '    - run: docker --context default buildx imagetools inspect --raw "$IMAGE"'
expect 0 imagetools-inspect "$DIR/imagetools-inspect.yml"

fixture buildx-build-load '    - run: docker buildx build --load -t "$IMAGE" .'
expect 0 buildx-build-load "$DIR/buildx-build-load.yml"

fixture push-as-run-argument '    - run: docker run --rm "$IMAGE_ID" echo push'
expect 0 push-as-run-argument "$DIR/push-as-run-argument.yml"

# Names neither the pin nor the bare tag, so only the missing pin can fail it.
fixture run-global-option-without-pin '    - run: docker --config "$HOME/.docker" run --rm "$IMAGE" true'
expect 1 run-global-option-without-pin "$DIR/run-global-option-without-pin.yml"

fixture tag-global-option-without-pin '    - run: docker -H unix:///var/run/docker.sock image tag "$SOURCE" "$IMAGE"'
expect 1 tag-global-option-without-pin "$DIR/tag-global-option-without-pin.yml"

expect 1 missing-file "$DIR/missing-file.yml"

exit "$FAILED"
