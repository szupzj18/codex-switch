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
echo "demo written to $OUT (base path $BASE)"
