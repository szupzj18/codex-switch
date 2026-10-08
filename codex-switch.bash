# CodeX Switch — parallel multi-account manager for the OpenAI Codex CLI (bash wrapper)
# https://github.com/szupzj18/codex-switch
#
# Thin shell layer: all logic lives in cx_core.py (next to this file).
# Needs bash 3.2+. The prompt marker is exposed as $CX_PROMPT_TEXT, e.g.:
#   PS1='$CX_PROMPT_TEXT \u@\h:\w\$ '

CX_CORE="${CX_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cx_core.py}"
CX_AUTO_ACTIVE="" _CX_PRE_AUTO_HOME="" CX_AUTO_CLAUDE="" _CX_PRE_AUTO_CLAUDE="" CX_PROMPT_KIND="" CX_PROMPT_NAME="" CX_PROMPT_TEXT=""
_CX_BINDINGS="${CX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/codex-switch}/bindings.tsv"

if ! command -v python3 >/dev/null 2>&1; then
  cx() { echo "cx: python3 is required (CodeX Switch core is written in Python 3.8+)" >&2; return 1; }
  return 0 2>/dev/null || exit 0
fi

_cx_run() {
  local f rc
  f=$(mktemp "${TMPDIR:-/tmp}/cx.XXXXXX") || return 1
  CX_SHELL=bash CX_EVAL_FILE=$f CX_AUTO_ACTIVE=$CX_AUTO_ACTIVE CX_PRE_AUTO_HOME=$_CX_PRE_AUTO_HOME \
    CX_AUTO_CLAUDE=$CX_AUTO_CLAUDE CX_PRE_AUTO_CLAUDE=$_CX_PRE_AUTO_CLAUDE \
    python3 "$CX_CORE" "$@"
  rc=$?
  if [ -s "$f" ]; then . "$f"; fi
  rm -f "$f"
  return $rc
}

cx() { _cx_run "$@"; }

# bash has no chpwd hook: check $PWD from PROMPT_COMMAND instead.
_cx_prompt_hook() {
  if [ "$PWD" != "${_CX_LAST_PWD:-}" ]; then
    _CX_LAST_PWD=$PWD
    if [ -s "$_CX_BINDINGS" ] || [ -n "$CX_AUTO_ACTIVE" ] || [ -n "$CX_AUTO_CLAUDE" ]; then
      _cx_run apply "$PWD"
    fi
  fi
}

case $- in
  *i*)
    if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
      case " ${PROMPT_COMMAND[*]} " in
        *" _cx_prompt_hook "*) ;;
        *) PROMPT_COMMAND=(_cx_prompt_hook "${PROMPT_COMMAND[@]}") ;;
      esac
    else
      case ";${PROMPT_COMMAND:-};" in
        *";_cx_prompt_hook;"*) ;;
        *) PROMPT_COMMAND="_cx_prompt_hook${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
      esac
    fi
    ;;
esac
_cx_run apply "$PWD"

_cx_complete() {
  local cur=${COMP_WORDS[COMP_CWORD]} names
  names=$(CX_SHELL=bash python3 "$CX_CORE" names 2>/dev/null)
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "ls usage setup use login off add rm bind unbind binds prompt version help $names" -- "$cur"))
  else
    case ${COMP_WORDS[1]} in
      use|login|bind|rm) COMPREPLY=($(compgen -W "$names" -- "$cur")) ;;
    esac
  fi
}
complete -F _cx_complete cx
