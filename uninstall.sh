#!/bin/sh
# CodeX Switch uninstaller (POSIX sh)
#
#   sh uninstall.sh           remove the rc source blocks (data kept)
#   sh uninstall.sh --purge   also restore Claude status lines (cx hook remove --all)
#                             and delete the installed scripts
#
# Account data (~/.codex, ~/.codex-*) and the CodeX Switch registry
# (~/.config/codex-switch) are never deleted.

INSTALL_DIR="${CX_HOME:-$HOME/.codex-switch}"
MARK_BEGIN="# >>> codex-switch >>>"
MARK_END="# <<< codex-switch <<<"

strip_block() {
  rc="$1"
  if [ -f "$rc" ] && grep -qF "$MARK_BEGIN" "$rc"; then
    tmp="$rc.codex-switch.tmp"
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
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
FISH_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/codex-switch.fish"
if [ -f "$FISH_CONF" ] && grep -qF "$MARK_BEGIN" "$FISH_CONF"; then
  rm -f "$FISH_CONF"
  echo "removed $FISH_CONF"
  found=1
fi
[ "$found" = 1 ] || echo "no marker block found in zsh/bash/fish config"

# Claude Code accounts may route their status line through the usage relay
# (cx hook). Restore the original commands before the relay files go away.
CORE="$INSTALL_DIR/cx_core.py"
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

if [ "$1" = "--purge" ] && [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
  echo "deleted $INSTALL_DIR"
fi

echo "account data and bindings left untouched under ~/.codex* and ~/.config/codex-switch"
