#!/usr/bin/env bash
# Runs check-dockerfile-eol.sh in throwaway git repositories, so a check that
# stopped finding Dockerfiles or reading their eol attribute fails here
# instead of passing a repository whose rule is gone.
set -uo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/check-dockerfile-eol.sh"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

# Builds a repository named $1 with .gitattributes $2 and tracks the paths
# that follow.
repo() {
  local root="$DIR/$1" attrs="$2" path
  shift 2
  git init -q "$root"
  printf '%s\n' "$attrs" > "$root/.gitattributes"
  for path in "$@"; do
    mkdir -p "$root/$(dirname "$path")"
    echo 'FROM ubuntu:24.04' > "$root/$path"
  done
  git -C "$root" add -A
  echo "$root"
}

expect() {
  local want="$1" name="$2" root="$3" pattern="$4" out got=0
  out="$(cd "$root" && bash "$CHECK" 2>&1)" || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    FAILED=1
  elif ! grep -qF -- "$pattern" <<< "$out"; then
    echo "FAIL $name: output lacks '$pattern'"
    FAILED=1
  else
    echo "ok   $name"
  fi
}

RULES="$(printf '* text=auto\nDockerfile text eol=lf\n*.Dockerfile text eol=lf')"

ROOT="$(repo covered "$RULES" docker/Dockerfile docker/fixtures/a.Dockerfile)"
expect 0 covered "$ROOT" "checked 2 tracked Dockerfile(s)"

ROOT="$(repo no-rule '* text=auto' docker/Dockerfile)"
expect 1 no-rule "$ROOT" "::error file=docker/Dockerfile::eol is 'unspecified'"

ROOT="$(repo crlf "$(printf '* text=auto\nDockerfile text eol=crlf')" Dockerfile)"
expect 1 crlf "$ROOT" "eol is 'crlf'"

ROOT="$(repo suffix-uncovered "$(printf '* text=auto\nDockerfile text eol=lf')" docker/Dockerfile docker/b.Dockerfile)"
expect 1 suffix-uncovered "$ROOT" "::error file=docker/b.Dockerfile::"

ROOT="$(repo dotted-uncovered "$RULES" docker/Dockerfile docker/Dockerfile.dev)"
expect 1 dotted-uncovered "$ROOT" "::error file=docker/Dockerfile.dev::"

ROOT="$(repo text-unset "$(printf 'Dockerfile -text eol=lf')" Dockerfile)"
expect 1 text-unset "$ROOT" "text is unset"

ROOT="$(repo untracked "$RULES" docker/Dockerfile)"
echo 'FROM ubuntu:24.04' > "$ROOT/Dockerfile.untracked"
printf 'Dockerfile.untracked -text\n' >> "$ROOT/.gitattributes"
expect 0 untracked-ignored "$ROOT" "checked 1 tracked Dockerfile(s)"

ROOT="$(repo none "$RULES" README.md)"
expect 1 none-found "$ROOT" "no tracked Dockerfile found"

ROOT="$DIR/not-a-repo"
mkdir -p "$ROOT"
expect 1 not-a-repo "$ROOT" "git ls-files failed"

exit "$FAILED"
