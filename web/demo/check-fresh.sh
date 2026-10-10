#!/bin/sh
# Advisory: is the committed demo (docs/demo) built from the current dashboard? The bundle file names are
# content hashes, so a changed dashboard changes them. Compares a fresh build (first argument, made by
# build.sh) with docs/demo (or the second argument) and prints a CI warning when they differ. Always exits 0.
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
  echo "::warning title=docs/demo is out of date::The dashboard changed since docs/demo was built. Run 'sh web/demo/build.sh' and commit docs/demo."
  diff "$A" "$B" | head -10 || true
fi
exit 0
