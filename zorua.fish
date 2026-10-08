# Zorua — parallel multi-account manager for the OpenAI Codex CLI (fish wrapper)
# https://github.com/szupzj18/zorua
#
# Thin shell layer: all logic lives in cx_core.py (next to this file).
# The prompt marker is exposed as $CX_PROMPT_TEXT; add it to your prompt, e.g.
#   function fish_right_prompt; echo $CX_PROMPT_TEXT; end

set -g CX_CORE (test -n "$CX_CORE"; and echo $CX_CORE; or echo (dirname (realpath (status filename)))/cx_core.py)
set -g CX_AUTO_ACTIVE ""
set -g _CX_PRE_AUTO_HOME ""
set -g CX_AUTO_CLAUDE ""
set -g _CX_PRE_AUTO_CLAUDE ""
set -g CX_PROMPT_KIND ""
set -g CX_PROMPT_NAME ""
set -g CX_PROMPT_TEXT ""
set -g _CX_BINDINGS (test -n "$CX_CONFIG_DIR"; and echo $CX_CONFIG_DIR; or echo (test -n "$XDG_CONFIG_HOME"; and echo $XDG_CONFIG_HOME; or echo $HOME/.config)/zorua)/bindings.tsv

if not command -q python3
    function cx
        echo "cx: python3 is required (Zorua core is written in Python 3.8+)" >&2
        return 1
    end
    exit 0
end

function _cx_run
    set -l f (mktemp)
    env CX_SHELL=fish CX_EVAL_FILE=$f CX_AUTO_ACTIVE=$CX_AUTO_ACTIVE CX_PRE_AUTO_HOME=$_CX_PRE_AUTO_HOME \
        CX_AUTO_CLAUDE=$CX_AUTO_CLAUDE CX_PRE_AUTO_CLAUDE=$_CX_PRE_AUTO_CLAUDE \
        python3 $CX_CORE $argv
    set -l rc $status
    if test -s $f
        source $f
    end
    rm -f $f
    return $rc
end

function cx
    _cx_run $argv
end

function _cx_on_pwd --on-variable PWD
    if test -s $_CX_BINDINGS; or test -n "$CX_AUTO_ACTIVE"; or test -n "$CX_AUTO_CLAUDE"
        _cx_run apply $PWD
    end
end

_cx_run apply $PWD

complete -c cx -f
complete -c cx -n '__fish_use_subcommand' -a 'ls usage setup use login off add rm bind unbind binds hook prompt version help'
complete -c cx -n '__fish_use_subcommand' -a '(CX_SHELL=fish python3 $CX_CORE names 2>/dev/null)'
complete -c cx -n '__fish_seen_subcommand_from use login bind rm' -a '(CX_SHELL=fish python3 $CX_CORE names 2>/dev/null)'
