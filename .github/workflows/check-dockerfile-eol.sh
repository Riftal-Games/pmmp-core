#!/usr/bin/env bash
# Fails unless every Dockerfile tracked in the repository at the working
# directory checks out with LF endings per .gitattributes. CI checks out on
# Linux, where a lost eol=lf rule changes nothing, so only a Windows checkout
# would get CRLF, and docker/check-ubuntu-base.sh would then read a CR as part
# of each image name (#151, #152). Dockerfiles are found by name among the
# tracked files, so one added anywhere is covered without editing this script,
# and finding none fails rather than passing unchecked.
#
# Usage: check-dockerfile-eol.sh
set -uo pipefail

if ! TRACKED=$(git ls-files -z | tr '\0' '\n'); then
  echo "::error::git ls-files failed, so no Dockerfile was checked"
  exit 1
fi
mapfile -t FILES < <(grep -E '(^|/)(Dockerfile(\.[^/]*)?|[^/]*\.Dockerfile)$' <<< "$TRACKED")
if [ "${#FILES[@]}" = 0 ]; then
  echo "::error::no tracked Dockerfile found, so nothing was checked"
  exit 1
fi

FAILED=0
for FILE in "${FILES[@]}"; do
  EOL=$(git check-attr eol -- "$FILE" | sed 's/.*: eol: //')
  TEXT=$(git check-attr text -- "$FILE" | sed 's/.*: text: //')
  if [ "$EOL" != lf ]; then
    echo "::error file=$FILE::eol is '$EOL' in .gitattributes, expected lf"
    FAILED=1
  fi
  # An unset text attribute turns off conversion, so eol=lf alone would not
  # keep a CR out of the checkout.
  if [ "$TEXT" = unset ]; then
    echo "::error file=$FILE::text is unset in .gitattributes, so eol=lf is never applied"
    FAILED=1
  fi
done

echo "checked ${#FILES[@]} tracked Dockerfile(s)"
exit "$FAILED"
