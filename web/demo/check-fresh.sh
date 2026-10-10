#!/bin/sh
# Is the committed demo (docs/demo) built from the current dashboard? The bundle file names are content
# hashes, so a changed dashboard changes them. Compares a fresh build (first argument, made by build.sh)
# with docs/demo (or the second argument); exits 1 with a CI error when they differ. The names come out
# the same on macOS and Linux, so a difference means docs/demo really is behind.
BUILT="$1"
COMMITTED="${2:-$(cd "$(dirname "$0")/../.." && pwd)/docs/demo}"
names() { (cd "$1/_next/static" 2>/dev/null && find chunks media -type f 2>/dev/null | sort); }
A="$(mktemp)"; B="$(mktemp)"
trap 'rm -f "$A" "$B"' EXIT
names "$BUILT" > "$A"
names "$COMMITTED" > "$B"
if cmp -s "$A" "$B"; then
  echo "docs/demo is up to date"
else
  echo "::error title=docs/demo is out of date::The dashboard changed since docs/demo was built. Run 'sh web/demo/build.sh' and commit docs/demo."
  diff "$A" "$B" | head -10 || true
  exit 1
fi
