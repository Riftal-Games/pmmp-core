#!/usr/bin/env bash
# Runs tag-image-sha.sh against a stub `docker`, so a push to riftal is proven
# to tag and every other run, or an image another run rebuilt, is proven not
# to. CI's pull_request runs never reach the tag itself. The last case fails
# if docker-image-ci.yml stops labelling the build or stops calling the script
# once the smoke steps have passed.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/tag-image-sha.sh"
WORKFLOW="$HERE/docker-image-ci.yml"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0
SHA=0123456789abcdef0123456789abcdef01234567
ID=sha256:feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface

mkdir "$DIR/bin"
cat > "$DIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB_CALLS"
case "$1 $2" in
  "image inspect")
    FORMAT="$4" REF="$5"
    if [ -n "${STUB_MISSING:-}" ]; then
      echo "Error response from daemon: No such image: $REF" >&2
      exit 1
    fi
    case "$FORMAT" in
      *revision*) echo "${STUB_REVISION:-}" ;;
      *) [ "$REF" = local-pocketmine-mp ] && echo "$STUB_ID" || echo "${STUB_TAG_ID:-$STUB_ID}" ;;
    esac
    ;;
  "tag "*) ;;
  *) echo "stub docker: unexpected call: $*" >&2; exit 125 ;;
esac
EOF
chmod +x "$DIR/bin/docker"

# expect <exit status> <case name> <text the output must contain> <tags: yes|no> [VAR=value...]
expect() {
  local want="$1" name="$2" text="$3" tags="$4" got=0
  shift 4
  mkdir "$DIR/$name"
  : > "$DIR/$name/calls"
  env PATH="$DIR/bin:$PATH" STUB_CALLS="$DIR/$name/calls" STUB_ID="$ID" \
    STUB_REVISION="$SHA" GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/riftal GITHUB_SHA="$SHA" "$@" \
    bash "$SCRIPT" local-pocketmine-mp > "$DIR/$name/out" 2>&1 || got=$?
  local tagged=no
  grep -qxF "tag $ID local-pocketmine-mp:$SHA" "$DIR/$name/calls" && tagged=yes
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
  elif [ "$tagged" != "$tags" ]; then
    echo "FAIL $name: tagged=$tagged, expected $tags"
  elif grep -qE '^(rmi|image rm|image prune|untag)' "$DIR/$name/calls"; then
    echo "FAIL $name: removed an image or tag"
  elif ! grep -qF -- "$text" "$DIR/$name/out"; then
    echo "FAIL $name: output lacks: $text"
  else
    echo "ok   $name"
    return
  fi
  FAILED=1
  cat "$DIR/$name/out" "$DIR/$name/calls"
}

expect 0 push-to-riftal "tagged $ID as local-pocketmine-mp:$SHA" yes
expect 0 pull-request "only a push to riftal is tagged" no GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/pull/7/merge
expect 0 pull-request-from-riftal "only a push to riftal is tagged" no GITHUB_EVENT_NAME=pull_request
expect 0 dispatch-on-riftal "only a push to riftal is tagged" no GITHUB_EVENT_NAME=workflow_dispatch
expect 0 push-to-other-branch "only a push to riftal is tagged" no GITHUB_REF=refs/heads/riftal-next
expect 0 push-of-tag "only a push to riftal is tagged" no GITHUB_REF=refs/tags/riftal
expect 1 rebuilt-by-another-run "another run rebuilt it" no STUB_REVISION=89abcdef0123456789abcdef0123456789abcdef
expect 1 unlabelled-image "another run rebuilt it" no STUB_REVISION="<no value>"
expect 1 rebuilt-seen-on-pull-request "another run rebuilt it" no STUB_REVISION=89abcdef0123456789abcdef0123456789abcdef GITHUB_EVENT_NAME=pull_request
expect 1 no-image "no image local-pocketmine-mp" no STUB_MISSING=1
expect 1 short-sha "is not a full commit sha" no GITHUB_SHA=0123456
expect 1 no-sha "is not a full commit sha" no GITHUB_SHA=
expect 1 tag-lands-elsewhere "not the $ID this run built" yes STUB_TAG_ID=sha256:0000

LABELLED="$(grep -nF 'org.opencontainers.image.revision=${{ github.sha }}' "$WORKFLOW" | cut -d: -f1)"
CALLED="$(grep -nF 'bash .github/workflows/tag-image-sha.sh local-pocketmine-mp' "$WORKFLOW" | cut -d: -f1)"
LAST_SMOKE="$(grep -nF '.github/workflows/crash-boot-smoke.sh local-pocketmine-mp' "$WORKFLOW" | cut -d: -f1)"
if [ -z "$LABELLED" ]; then
  echo "FAIL workflow-wired: docker-image-ci.yml does not label the build with its revision"
  FAILED=1
elif [ -z "$CALLED" ] || [ -z "$LAST_SMOKE" ] || [ "$CALLED" -le "$LAST_SMOKE" ]; then
  echo "FAIL workflow-wired: docker-image-ci.yml does not call tag-image-sha.sh after its last smoke step"
  FAILED=1
else
  echo "ok   workflow-wired"
fi

exit "$FAILED"
