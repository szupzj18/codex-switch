# CodeX Switch — parallel multi-account manager for the OpenAI Codex CLI (zsh wrapper)
# https://github.com/szupzj18/codex-switch
#
# Thin shell layer: all logic lives in cx_core.py (next to this file). This
# wrapper runs it, then sources whatever shell statements it requested
# (CODEX_HOME, auto-binding state, prompt marker), and adds the cd hook,
# right-prompt marker and tab completion.

typeset -g CX_CORE="${CX_CORE:-${${(%):-%x}:A:h}/cx_core.py}"
typeset -g CX_AUTO_ACTIVE="" _CX_PRE_AUTO_HOME="" CX_AUTO_CLAUDE="" _CX_PRE_AUTO_CLAUDE="" CX_PROMPT_KIND="" CX_PROMPT_NAME="" CX_PROMPT_TEXT=""
typeset -g _CX_BINDINGS="${CX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/codex-switch}/bindings.tsv"

if ! (( $+commands[python3] )); then
  cx() { print "cx: python3 is required (CodeX Switch core is written in Python 3.8+)" >&2; return 1 }
  return 0
fi

# Run the core, then apply the shell changes it asked for.
_cx_run() {
  local f rc
  f=$(mktemp "${TMPDIR:-/tmp}/cx.XXXXXX") || return 1
  CX_SHELL=zsh CX_EVAL_FILE=$f CX_AUTO_ACTIVE=$CX_AUTO_ACTIVE CX_PRE_AUTO_HOME=$_CX_PRE_AUTO_HOME \
    CX_AUTO_CLAUDE=$CX_AUTO_CLAUDE CX_PRE_AUTO_CLAUDE=$_CX_PRE_AUTO_CLAUDE \
    python3 "$CX_CORE" "$@"
  rc=$?
  if [[ -s $f ]]; then source "$f"; fi
  rm -f "$f"
  _cx_rprompt
  return $rc
}

cx() { _cx_run "$@" }

_cx_rprompt() {
  case $CX_PROMPT_KIND in
    "")     RPROMPT="" ;;
    auto)   RPROMPT="%F{yellow}${CX_PROMPT_TEXT}%f" ;;
    *)      RPROMPT="%F{cyan}${CX_PROMPT_TEXT}%f" ;;
  esac
}

# cd hook: only spawn the core when a binding could matter.
_cx_apply_binding() {
  if [[ -s $_CX_BINDINGS || -n $CX_AUTO_ACTIVE || -n $CX_AUTO_CLAUDE ]]; then
    _cx_run apply "$PWD"
  fi
}

if [[ -o interactive ]]; then
  if [[ -z ${precmd_functions[(r)_cx_rprompt]} ]]; then
    precmd_functions+=(_cx_rprompt)
  fi
  if [[ -z ${chpwd_functions[(r)_cx_apply_binding]} ]]; then
    chpwd_functions=(_cx_apply_binding $chpwd_functions)
  fi
fi
# Initial state: honor an inherited CODEX_HOME and any binding for $PWD.
_cx_run apply "$PWD"

_cx() {
  local -a names
  names=(${(f)"$(CX_SHELL=zsh python3 $CX_CORE names 2>/dev/null)"})
  if (( CURRENT == 2 )); then
    _alternative \
      'subcommands:cx command:(ls usage setup use login off add rm bind unbind binds prompt version help)' \
      "accounts:codex account:($names)"
  elif (( CURRENT == 3 )); then
    case $words[2] in
      use|login|bind) _wanted accounts expl 'codex account' compadd -- $names ;;
      rm) _wanted accounts expl 'codex account' compadd -- ${names:#default} ;;
    esac
  fi
}
(( $+functions[compdef] )) && compdef _cx cx
return 0
