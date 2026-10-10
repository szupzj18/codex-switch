#!/bin/sh
# Build the static demo of the dashboard: the real app, with /api/* answered in the browser from made-up
# data (demo/overlay/app/demo.tsx), exported as plain files. Output goes to docs/demo/ (GitHub Pages) or to
# the directory given as the first argument. Needs `npm ci` in web/ first. Usage: sh demo/build.sh [outdir]
#
# The real app is not touched: the build runs on a copy in web/.demo-build, minus app/api, with the files
# in demo/overlay on top (static export config, a layout that loads the fake backend).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
WEB="$(cd "$HERE/.." && pwd)"
OUT="${1:-$WEB/../docs/demo}"
BASE="${ZORUA_DEMO_BASE:-/zorua/demo}"
TMP="$WEB/.demo-build"

# The output directory is replaced, so refuse one that holds something else (`sh build.sh .` or `~`).
if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ] && [ ! -f "$OUT/.zorua-demo" ] && ! { [ -d "$OUT/_next" ] && [ -f "$OUT/index.html" ]; }; then
  echo "refusing to replace $OUT: it is not empty and does not look like an earlier demo build" >&2
  exit 1
fi

rm -rf "$TMP"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/lib"
cp -R "$WEB/app" "$TMP/app"
rm -rf "$TMP/app/api"
cp "$WEB/lib/types.ts" "$TMP/lib/types.ts"
cp "$WEB/package.json" "$WEB/tsconfig.json" "$TMP/"
cp -R "$HERE/overlay/." "$TMP/"

# No lockfile in the copy: Next then takes web/ as its root and finds web/node_modules.
(cd "$TMP" && NEXT_TELEMETRY_DISABLED=1 NEXT_PUBLIC_BASE_PATH="$BASE" ZORUA_DEMO_BASE="$BASE" npx next build)

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$TMP/out/." "$OUT/"
touch "$OUT/.zorua-demo"   # marks the directory as ours, so the next build may replace it
echo "demo written to $OUT (base path $BASE)"
