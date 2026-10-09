#!/bin/sh
# Install, remove or inspect the Zorua web dashboard as a macOS LaunchAgent.
#
#   sh launchd/zorua-web.sh install     build, write the plist, start it now and at every login
#   sh launchd/zorua-web.sh uninstall   stop it and remove the plist
#   sh launchd/zorua-web.sh status
#
# Environment: ZORUA_CORE (default ~/.zorua/zorua_core.py), ZORUA_WEB_PORT (default 4747),
# ZORUA_WEB_PROXY (default: your shell's HTTPS_PROXY). install refuses to run without a proxy,
# because a LaunchAgent does not inherit one and zorua's usage requests would go out directly.
set -e

LABEL="org.zorua.web"
PORT="${ZORUA_WEB_PORT:-4747}"
WEB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/zorua-web.log"
CORE="${ZORUA_CORE:-$HOME/.zorua/zorua_core.py}"
DOMAIN="gui/$(id -u)"

case "$1" in
install)
  command -v node >/dev/null 2>&1 || { echo "node not found on PATH" >&2; exit 1; }
  [ -f "$CORE" ] || { echo "zorua core not found: $CORE" >&2; exit 1; }
  PROXY="${ZORUA_WEB_PROXY:-${HTTPS_PROXY:-${https_proxy:-}}}"
  [ -n "$PROXY" ] || { echo "no proxy: set ZORUA_WEB_PROXY (or HTTPS_PROXY), e.g. ZORUA_WEB_PROXY=http://127.0.0.1:7897" >&2; exit 1; }
  NODE="$(command -v node)"
  (cd "$WEB_DIR" && npm ci && npm run build)
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE</string>
    <string>$WEB_DIR/node_modules/next/dist/bin/next</string>
    <string>start</string>
    <string>-H</string><string>127.0.0.1</string>
    <string>-p</string><string>$PORT</string>
  </array>
  <key>WorkingDirectory</key><string>$WEB_DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ZORUA_CORE</key><string>$CORE</string>
    <key>HTTPS_PROXY</key><string>$PROXY</string>
    <key>HTTP_PROXY</key><string>$PROXY</string>
    <key>NO_PROXY</key><string>localhost,127.0.0.1,::1</string>
    <key>PATH</key><string>$(dirname "$NODE"):/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$PLIST"
  echo "running: http://127.0.0.1:$PORT  (log: $LOG)"
  ;;
uninstall)
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "removed $LABEL"
  ;;
status)
  launchctl print "$DOMAIN/$LABEL" 2>/dev/null | sed -n '1,12p' || true
  ;;
*)
  echo "usage: sh $0 install|uninstall|status" >&2
  exit 2
  ;;
esac
