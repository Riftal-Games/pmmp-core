#!/usr/bin/env bash
# Runs check-run-expressions.sh against fixture workflows, so a check that
# stopped seeing an expression inside a run: script fails here instead of
# passing the publish workflow quietly.
set -uo pipefail

CHECK="$(dirname "$0")/check-run-expressions.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

expect() {
  local want="$1" name="$2" body="$3" got=0
  printf '%s\n' "$body" > "$DIR/$name.yml"
  bash "$CHECK" "$DIR/$name.yml" > /dev/null 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    FAILED=1
  else
    echo "ok   $name"
  fi
}

expect 0 through-env "$(cat <<'EOF'
jobs:
  build:
    steps:
      - uses: actions/checkout@v7
        with:
          ref: refs/tags/${{ github.event.inputs.release }}
      - name: Tag
        env:
          TAG_NAME: ${{ github.event.inputs.release }}
        run: |
          echo "$TAG_NAME"
      - run: echo done
EOF
)"
expect 1 inline "$(cat <<'EOF'
jobs:
  build:
    steps:
      - name: Download
        run: curl -f "${{ steps.tag-name.outputs.TAG_NAME }}"
EOF
)"
expect 1 inline-dash "$(cat <<'EOF'
jobs:
  build:
    steps:
    - run: echo ${{ github.event.release.tag_name }}
EOF
)"
expect 1 block "$(cat <<'EOF'
jobs:
  build:
    steps:
      - name: Tag
        run: |
          set -e

          echo TAG_NAME="${{ github.event.inputs.release }}" >> "$GITHUB_OUTPUT"
      - run: echo done
EOF
)"
expect 1 folded-block "$(cat <<'EOF'
jobs:
  build:
    steps:
      - run: >-
          docker push ghcr.io/x:${{ steps.version.outputs.MAJOR }}
EOF
)"
expect 1 shell-comment "$(cat <<'EOF'
jobs:
  build:
    steps:
      - run: |
          # ${{ github.event.inputs.release }}
          true
EOF
)"
expect 1 second-step "$(cat <<'EOF'
jobs:
  build:
    steps:
      - run: |
          echo "$TAG_NAME"
      - run: |
          echo ${{ github.event_name }}
EOF
)"
expect 1 no-run "$(cat <<'EOF'
jobs:
  build:
    steps:
      - uses: actions/checkout@v7
EOF
)"

got=0
bash "$CHECK" "$DIR/missing-file.yml" > /dev/null 2>&1 || got=$?
if [ "$got" != 1 ]; then
  echo "FAIL missing-file: exit $got, expected 1"
  FAILED=1
else
  echo "ok   missing-file"
fi

exit "$FAILED"
