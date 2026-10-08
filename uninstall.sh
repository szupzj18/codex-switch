#!/bin/sh
# Zorua uninstaller (POSIX sh)
#
#   sh uninstall.sh           remove the rc source blocks (data kept)
#   sh uninstall.sh --purge   also restore Claude status lines (zorua hook remove --all)
#                             and delete the installed scripts
#
# Account data (~/.codex, ~/.codex-*) and the Zorua registry
# (~/.config/zorua) are never deleted.

INSTALL_DIR="${ZORUA_HOME:-${CX_HOME:-$HOME/.zorua}}"
MARK_BEGIN="# >>> zorua >>>"
MARK_END="# <<< zorua <<<"
LEGACY_DIR="$HOME/.codex-switch"
LEGACY_BEGIN="# >>> codex-switch >>>"
LEGACY_END="# <<< codex-switch <<<"

strip_block() {
  rc="$1"; begin="${2:-$MARK_BEGIN}"; end="${3:-$MARK_END}"
  if [ -f "$rc" ] && grep -qF "$begin" "$rc"; then
    tmp="$rc.zorua.tmp"
    awk -v b="$begin" -v e="$end" '
      $0 == b { skip=1; next }
      $0 == e { skip=0; next }
      skip != 1 { print }
    ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    echo "removed source block from $rc"
    return 0
  fi
  return 1
}

found=0
strip_block "${ZDOTDIR:-$HOME}/.zshrc" && found=1
strip_block "$HOME/.bashrc" && found=1
# leftovers of the old codex-switch name
strip_block "${ZDOTDIR:-$HOME}/.zshrc" "$LEGACY_BEGIN" "$LEGACY_END" && found=1
strip_block "$HOME/.bashrc" "$LEGACY_BEGIN" "$LEGACY_END" && found=1
OLD_FISH="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/codex-switch.fish"
if [ -f "$OLD_FISH" ] && grep -qF "$LEGACY_BEGIN" "$OLD_FISH"; then
  rm -f "$OLD_FISH"
  echo "removed $OLD_FISH"
  found=1
fi
FISH_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/zorua.fish"
if [ -f "$FISH_CONF" ] && grep -qF "$MARK_BEGIN" "$FISH_CONF"; then
  rm -f "$FISH_CONF"
  echo "removed $FISH_CONF"
  found=1
fi
[ "$found" = 1 ] || echo "no marker block found in zsh/bash/fish config"

# Claude Code accounts may route their status line through the usage relay
# (zorua hook). Restore the original commands before the relay files go away.
CORE="$INSTALL_DIR/zorua_core.py"
[ -f "$CORE" ] || CORE="$INSTALL_DIR/cx_core.py"   # install from before the command rename
[ -f "$CORE" ] || CORE="$LEGACY_DIR/cx_core.py"
if [ -f "$CORE" ] && command -v python3 >/dev/null 2>&1; then
  if [ "$1" = "--purge" ]; then
    python3 "$CORE" hook remove --all
  else
    n=$(python3 "$CORE" hook status 2>/dev/null | grep -c '^relay:    installed')
    if [ "${n:-0}" -gt 0 ]; then
      echo "note: $n Claude account(s) still use the usage relay (files kept, so it keeps working)."
      echo "      Restore their status lines first with: python3 \"$CORE\" hook remove --all"
    fi
  fi
fi

if [ "$1" = "--purge" ]; then
  for d in "$INSTALL_DIR" "$LEGACY_DIR"; do
    if [ -d "$d" ]; then
      rm -rf "$d"
      echo "deleted $d"
    fi
  done
fi

echo "account data and bindings left untouched under ~/.codex* and ~/.config/zorua"
