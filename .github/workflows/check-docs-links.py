#!/usr/bin/env python3
"""
Fails on a relative link in docs/**/*.md to a file that does not exist, a
heading anchor that names no heading in its target, and any line-number
citation into a markdown file (#37).

Prose moves whenever anyone edits it, so a line number into a document is
only right until the next commit touches that document, and a stale one
looks exactly as authoritative as a correct one. A document is cited by
heading instead, which this script can resolve. Line citations into source
files are left alone: source moves far less often than prose, and no
expected text exists here to check them against.

Anchors follow GitHub's slugs: lower case, punctuation other than - and _
dropped, each space a hyphen, and a repeated heading suffixed -1, -2 and so
on. Fenced code blocks are skipped, and inline code is skipped for links but
not for citations, since a citation is usually written as code.

Usage: check-docs-links.py [ROOT], where ROOT defaults to the working
directory and holds the docs/ directory to check.
"""

import os
import re
import sys
from urllib.parse import unquote

FENCE = re.compile(r"^\s*(```|~~~)")
HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")
HTML_ANCHOR = re.compile(r"<a\s+(?:name|id)=\"([^\"]+)\"")
CODE_SPAN = re.compile(r"(`+).*?\1")
INLINE_LINK = re.compile(r"!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^)\s>]*)>?(?:\s+\"[^\"]*\")?\s*\)")
REF_DEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?([^\s>]+)>?")
EXTERNAL = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
MD_LINE_CITE = re.compile(r"[\w./-]+\.(?:md|markdown):\d+")
MD_LINE_ANCHOR = re.compile(r"^L\d+")


def prose_lines(path):
    """Yields (line number, text) for each line outside a fenced block."""
    fence = None
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            match = FENCE.match(line)
            if fence is None and match:
                fence = match.group(1)
            elif fence is not None and line.strip().startswith(fence):
                fence = None
            elif fence is None:
                yield number, line.rstrip("\n")


def slug(text):
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    return re.sub(r"[^\w\- ]", "", text.lower()).replace(" ", "-")


def anchors(path, cache={}):
    if path not in cache:
        seen = {}
        found = set()
        for _, line in prose_lines(path):
            found.update(HTML_ANCHOR.findall(line))
            match = HEADING.match(line)
            if not match:
                continue
            base = slug(match.group(1))
            count = seen.get(base, 0)
            seen[base] = count + 1
            found.add(base if count == 0 else f"{base}-{count}")
        cache[path] = found
    return cache[path]


def check_file(root, path):
    rel = os.path.relpath(path, root).replace(os.sep, "/")
    errors = []
    links = 0
    for number, line in prose_lines(path):
        for cite in MD_LINE_CITE.findall(line):
            errors.append((number, f"line-number citation {cite} into a markdown file, cite its heading instead"))
        bare = CODE_SPAN.sub("", line)
        targets = INLINE_LINK.findall(bare) + REF_DEF.findall(bare)
        for target in targets:
            if not target or EXTERNAL.match(target):
                continue
            links += 1
            file_part, _, anchor = unquote(target).partition("#")
            dest = os.path.normpath(os.path.join(os.path.dirname(path), file_part)) if file_part else path
            if not os.path.exists(dest):
                errors.append((number, f"link to {file_part}, which does not exist"))
                continue
            if not anchor or not dest.endswith((".md", ".markdown")):
                continue
            if MD_LINE_ANCHOR.match(anchor):
                errors.append((number, f"line anchor #{anchor} into a markdown file, cite its heading instead"))
            elif anchor not in anchors(dest):
                errors.append((number, f"anchor #{anchor} names no heading in {file_part or rel}"))
    for number, message in errors:
        print(f"::error file={rel},line={number}::{message}")
    return links, len(errors)


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    docs = os.path.join(root, "docs")
    files = sorted(
        os.path.join(directory, name)
        for directory, _, names in os.walk(docs)
        for name in names
        if name.endswith((".md", ".markdown"))
    )
    if not files:
        print(f"::error::no markdown found under {docs}, so nothing was checked")
        return 1
    links = errors = 0
    for path in files:
        found, failed = check_file(root, path)
        links += found
        errors += failed
    print(f"checked {len(files)} document(s), {links} relative link(s), {errors} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
