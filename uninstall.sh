#!/bin/zsh
# CodeX Switch uninstaller
#
#   zsh uninstall.sh           remove the zshrc source block (data kept)
#   zsh uninstall.sh --purge   also delete the installed script
#
# Account data (~/.codex, ~/.codex-*) and the CodeX Switch registry
# (~/.config/codex-switch) are never deleted.

emulate -L zsh

INSTALL_DIR="${CX_HOME:-$HOME/.codex-switch}"
DEST="$INSTALL_DIR/codex-switch.zsh"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
MARK_BEGIN="# >>> codex-switch >>>"
MARK_END="# <<< codex-switch <<<"

if [[ -f $ZSHRC ]] && grep -qF "$MARK_BEGIN" "$ZSHRC"; then
  tmp="${ZSHRC}.codex-switch.tmp"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0 == b { skip=1; next }
    $0 == e { skip=0; next }
    skip != 1 { print }
  ' "$ZSHRC" >! "$tmp" && mv "$tmp" "$ZSHRC"
  print "removed source block from $ZSHRC"
else
  print "no marker block found in $ZSHRC"
fi

if [[ $1 == --purge && -d $INSTALL_DIR ]]; then
  rm -rf "$INSTALL_DIR"
  print "deleted $INSTALL_DIR"
fi

print "account data and bindings left untouched under ~/.codex* and ~/.config/codex-switch"
