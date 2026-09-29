#!/usr/bin/env bash
# Fixtures are workflow text, so "$IMAGE_ID" in single quotes is meant literally.
# shellcheck disable=SC2016
#
# Runs check-pinned-image.sh against docker-image-ci.yml itself and against
# copies of it with one "$IMAGE_ID" at a time put back to the bare tag, so
# every step that runs or tags the image, including one added later, is
# proven to fail the check when it stops naming the pinned ID. Fixtures cover
# the comment and continuation handling the real file does not exercise.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-pinned-image.sh"
WORKFLOW="$HERE/docker-image-ci.yml"
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

expect 0 docker-image-ci "$WORKFLOW"

tr -d '\r' < "$WORKFLOW" | sed 's/$/\r/' > "$DIR/crlf.yml"
expect 0 docker-image-ci-crlf "$DIR/crlf.yml"

# Every "$IMAGE_ID" on a line that is not a comment, reverted one at a time.
mapfile -t LINES < <(grep -nF -- "$PINNED" "$WORKFLOW" | grep -vE '^[0-9]+:[[:space:]]*#' | cut -d: -f1)
if [ "${#LINES[@]}" -lt 7 ]; then
  echo "FAIL reverts: found ${#LINES[@]} pinned line(s) in docker-image-ci.yml, expected at least 7"
  FAILED=1
fi
for LINE in "${LINES[@]}"; do
  awk -v n="$LINE" -v p="$PINNED" 'NR == n { i = index($0, p); $0 = substr($0, 1, i - 1) "local-pocketmine-mp" substr($0, i + length(p)) } { print }' \
    "$WORKFLOW" > "$DIR/revert-$LINE.yml"
  expect 1 "revert-line-$LINE" "$DIR/revert-$LINE.yml"
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

fixture pin-only-in-trailing-comment '    - run: docker run --rm local-pocketmine-mp true # "$IMAGE_ID"'
expect 1 pin-only-in-trailing-comment "$DIR/pin-only-in-trailing-comment.yml"

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

expect 1 missing-file "$DIR/missing-file.yml"

exit "$FAILED"
