#!/bin/sh
# CodeX Switch installer (POSIX sh — run it with sh, bash or zsh)
#
#   curl -fsSL https://raw.githubusercontent.com/szupzj18/codex-switch/main/install.sh | sh
#
# Or from a clone:
#   sh install.sh
#
# Installs the Python core plus the zsh/bash/fish wrappers into
# ~/.codex-switch and wires up the shells it finds (zsh, bash, fish).
#
# Environment:
#   CX_HOME  install destination (default: ~/.codex-switch)

set -e

REPO_OWNER="szupzj18"
REPO_NAME="codex-switch"
BRANCH="main"
INSTALL_DIR="${CX_HOME:-$HOME/.codex-switch}"
FILES="cx_core.py codex-switch.zsh codex-switch.bash codex-switch.fish"
MARK_BEGIN="# >>> codex-switch >>>"
MARK_END="# <<< codex-switch <<<"

say() { printf '%s\n' "$*"; }

# --- python3 (the core is Python 3.8+) --------------------------------------
if command -v python3 >/dev/null 2>&1; then
  if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
    say "warning: python3 is older than 3.8; CodeX Switch needs Python 3.8+" >&2
  fi
else
  say "warning: python3 not found. CodeX Switch needs Python 3.8+ — install it, then open a new shell." >&2
fi

# --- copy files --------------------------------------------------------------
mkdir -p "$INSTALL_DIR"
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || script_dir=""
if [ -n "$script_dir" ] && [ -f "$script_dir/cx_core.py" ]; then
  for f in $FILES; do cp "$script_dir/$f" "$INSTALL_DIR/$f"; done
  say "installed from local clone: $script_dir"
else
  for f in $FILES; do
    url="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH/$f"
    say "downloading $url"
    if ! curl -fsSL "$url" -o "$INSTALL_DIR/$f.part"; then
      rm -f "$INSTALL_DIR/$f.part"
      say "download failed (private repo? clone it and run 'sh install.sh')" >&2
      exit 1
    fi
    mv "$INSTALL_DIR/$f.part" "$INSTALL_DIR/$f"
  done
fi
chmod +x "$INSTALL_DIR/cx_core.py"

# --- wire up shells ----------------------------------------------------------
# add_block <rc file> <source line> <shell>: append a marked block once.
add_block() {
  rc="$1"; line="$2"
  mkdir -p "$(dirname "$rc")"
  touch "$rc"
  if grep -qF "$MARK_BEGIN" "$rc"; then
    say "source block already present, left untouched: $rc"
  elif grep -qF "codex-switch.$3" "$rc"; then
    say "warning: $rc already references codex-switch.$3 without marker block;"
    say "         add this line manually if needed:"
    say "         $line"
  else
    {
      printf '\n%s\n' "$MARK_BEGIN"
      printf '%s\n' "$line"
      printf '%s\n' "$MARK_END"
    } >> "$rc"
    say "added source block to $rc"
  fi
}

wired=""
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
if command -v zsh >/dev/null 2>&1 || [ -f "$ZSHRC" ]; then
  add_block "$ZSHRC" "source \"$INSTALL_DIR/codex-switch.zsh\"" zsh
  wired="$wired zsh"
fi

BASHRC="$HOME/.bashrc"
use_bash=0
if [ -f "$BASHRC" ]; then use_bash=1; fi
case "${SHELL:-}" in */bash) use_bash=1 ;; esac
if [ "$use_bash" = 1 ]; then
  add_block "$BASHRC" ". \"$INSTALL_DIR/codex-switch.bash\"" bash
  wired="$wired bash"
  if [ -f "$HOME/.bash_profile" ] && ! grep -q 'bashrc' "$HOME/.bash_profile"; then
    say "note: ~/.bash_profile does not load ~/.bashrc; login shells (macOS Terminal) need:"
    say "      [ -f ~/.bashrc ] && . ~/.bashrc"
  fi
fi

FISH_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
FISH_CONF="$FISH_DIR/conf.d/codex-switch.fish"
if command -v fish >/dev/null 2>&1 || [ -d "$FISH_DIR" ]; then
  mkdir -p "$FISH_DIR/conf.d"
  if [ -f "$FISH_CONF" ] && grep -qF "$MARK_BEGIN" "$FISH_CONF"; then
    say "source block already present, left untouched: $FISH_CONF"
  else
    {
      printf '%s\n' "$MARK_BEGIN"
      printf 'source "%s/codex-switch.fish"\n' "$INSTALL_DIR"
      printf '%s\n' "$MARK_END"
    } > "$FISH_CONF"
    say "added source block to $FISH_CONF"
  fi
  wired="$wired fish"
fi

if [ -z "$wired" ]; then
  say "no zsh/bash/fish found; source one of these from your shell's rc file:"
  say "  $INSTALL_DIR/codex-switch.zsh | .bash | .fish"
fi

if command -v codex >/dev/null 2>&1; then
  say "detected codex: $(codex --version 2>/dev/null || echo 'unknown version')"
else
  say ""
  say "note: codex CLI not found on PATH. Install it first:"
  say "      curl -fsSL https://chatgpt.com/codex/install.sh | sh"
fi

say ""
say "done (shells:${wired:- none}). Open a new terminal, then run: cx setup   (or: cx help)"
