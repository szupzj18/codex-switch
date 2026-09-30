#!/bin/zsh
# codex-cx installer
#
#   curl -fsSL https://raw.githubusercontent.com/szupzj18/codex-cx/main/install.sh | zsh
#
# Or from a clone:
#   zsh install.sh
#
# Environment:
#   CX_HOME  install destination for the script (default: ~/.codex-cx)

emulate -L zsh
set -e

REPO_OWNER="szupzj18"
REPO_NAME="codex-cx"
BRANCH="main"
INSTALL_DIR="${CX_HOME:-$HOME/.codex-cx}"
DEST="$INSTALL_DIR/codex-cx.zsh"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
MARK_BEGIN="# >>> codex-cx >>>"
MARK_END="# <<< codex-cx <<<"

if [[ -z $ZSH_VERSION ]]; then
  print "codex-cx requires zsh. Run this script with zsh." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"

script_dir="${0:A:h}"
if [[ -f "$script_dir/codex-cx.zsh" ]]; then
  cp "$script_dir/codex-cx.zsh" "$DEST"
  print "installed from local clone: $script_dir/codex-cx.zsh"
else
  url="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH/codex-cx.zsh"
  print "downloading $url"
  if ! curl -fsSL "$url" -o "$DEST.part"; then
    print "download failed (private repo? clone it and run 'zsh install.sh')" >&2
    exit 1
  fi
  mv "$DEST.part" "$DEST"
fi

touch "$ZSHRC"
if grep -qF "$MARK_BEGIN" "$ZSHRC"; then
  print "zshrc block already present, left untouched: $ZSHRC"
elif grep -qF "codex-cx.zsh" "$ZSHRC"; then
  print "warning: $ZSHRC already references codex-cx.zsh without marker block;"
  print "         add this line manually if needed:"
  print "         source \"$DEST\""
else
  {
    print ""
    print "$MARK_BEGIN"
    print "source \"$DEST\""
    print "$MARK_END"
  } >> "$ZSHRC"
  print "added source block to $ZSHRC"
fi

if (( $+commands[codex] )); then
  print "detected codex: $(codex --version 2>/dev/null || print 'unknown version')"
else
  print ""
  print "note: codex CLI not found on PATH. Install it first:"
  print "      curl -fsSL https://chatgpt.com/codex/install.sh | sh"
fi

print ""
print "done. Open a new terminal (or: source $ZSHRC), then run: cx help"
