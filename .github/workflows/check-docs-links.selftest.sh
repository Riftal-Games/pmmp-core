#!/usr/bin/env bash
# Runs check-docs-links.py against fixture docs/ trees, so a check that
# stopped resolving links, anchors or citations fails here instead of passing
# documents that are broken. Every broken case also needs the error text
# naming its line, so a crash or a different error cannot stand in for it.
set -uo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/check-docs-links.py"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
FAILED=0

# Builds a tree named $1 whose docs/a.md is $2, next to a fixed docs/b.md.
tree() {
  local root="$DIR/$1"
  mkdir -p "$root/docs/sub" "$root/src"
  printf '%s\n' "$2" > "$root/docs/a.md"
  cat > "$root/docs/sub/b.md" <<'EOF'
# B
## What "tier" means here
## What `x.y-z` gates
## SELF_SIGNED, and more
## Repeat
## Repeat
<a name="custom"></a>
```
## Not a heading
```
EOF
  echo '<?php' > "$root/src/Foo.php"
  echo "$root"
}

expect() {
  local want="$1" name="$2" root="$3" pattern="$4" out got=0
  out="$(python3 "$CHECK" "$root" 2>&1)" || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, expected $want"
    echo "$out"
    FAILED=1
  elif ! grep -qF -- "$pattern" <<< "$out"; then
    echo "FAIL $name: output lacks '$pattern'"
    echo "$out"
    FAILED=1
  else
    echo "ok   $name"
  fi
}

GOOD=$(cat <<'EOF'
# A
## Local heading
[b](sub/b.md) [tier](sub/b.md#what-tier-means-here) [code](sub/b.md#what-xy-z-gates)
[signed](sub/b.md#self_signed-and-more) [second](sub/b.md#repeat-1) [named](sub/b.md#custom)
[here](#local-heading) [web](https://example.com/x.md#nope) [src](../src/Foo.php)
![img](sub/b.md "title") [ref][r] `[code](missing.md)` cited at `src/Foo.php:12`

[r]: sub/b.md#b

```
[fenced](missing.md) docs/sub/b.md:3
```
EOF
)
expect 0 good "$(tree good "$GOOD")" "checked 2 document(s), 10 relative link(s), 0 error(s)"

expect 1 missing-file "$(tree missing-file $'# A\n\n[gone](sub/gone.md)')" \
  "::error file=docs/a.md,line=3::link to sub/gone.md, which does not exist"
expect 1 missing-ref "$(tree missing-ref $'# A\n[r]: ../src/Gone.php')" \
  "::error file=docs/a.md,line=2::link to ../src/Gone.php, which does not exist"
expect 1 dead-anchor "$(tree dead-anchor $'# A\n[b](sub/b.md#what-tier-means)')" \
  "::error file=docs/a.md,line=2::anchor #what-tier-means names no heading in sub/b.md"
expect 1 fenced-heading "$(tree fenced-heading $'# A\n[b](sub/b.md#not-a-heading)')" \
  "anchor #not-a-heading names no heading"
expect 1 third-repeat "$(tree third-repeat $'# A\n[b](sub/b.md#repeat-2)')" \
  "anchor #repeat-2 names no heading"
expect 1 dead-local-anchor "$(tree dead-local-anchor $'# A\n[here](#nowhere)')" \
  "::error file=docs/a.md,line=2::anchor #nowhere names no heading in docs/a.md"
expect 1 md-line-cite "$(tree md-line-cite $'# A\nsee `sub/b.md:3`')" \
  "::error file=docs/a.md,line=2::line-number citation sub/b.md:3 into a markdown file"
expect 1 md-range-cite "$(tree md-range-cite $'# A\nsee ../../docs/roadmap.md:26-167')" \
  "line-number citation ../../docs/roadmap.md:26 into a markdown file"
expect 1 md-line-anchor "$(tree md-line-anchor $'# A\n[b](sub/b.md#L3)')" \
  "::error file=docs/a.md,line=2::line anchor #L3 into a markdown file"

mkdir -p "$DIR/empty/docs"
expect 1 none-found "$DIR/empty" "no markdown found under"

exit "$FAILED"
