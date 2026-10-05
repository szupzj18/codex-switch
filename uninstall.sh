#!/bin/sh
# CodeX Switch uninstaller (POSIX sh)
#
#   sh uninstall.sh           remove the rc source blocks (data kept)
#   sh uninstall.sh --purge   also delete the installed scripts
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

if [ "$1" = "--purge" ] && [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
  echo "deleted $INSTALL_DIR"
fi

echo "account data and bindings left untouched under ~/.codex* and ~/.config/codex-switch"
