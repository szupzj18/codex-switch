#!/usr/bin/env fish
# CodeX Switch smoke test for the fish wrapper — runs inside a temporary HOME.
#
#   fish tests/smoke.fish

set -l root (dirname (dirname (realpath (status filename))))
set -l tmp (mktemp -d)
set -gx HOME $tmp/home
set -gx XDG_CONFIG_HOME $tmp/config
set -e CODEX_HOME
mkdir -p $HOME

set -g n 0
function ok
    set -g n (math $n + 1)
    echo "ok $argv"
end
function die
    echo "FAIL $argv" >&2
    rm -rf $tmp
    exit 1
end
function contains_str
    # contains_str <haystack> <needle> <label>
    string match -q -- "*$argv[2]*" $argv[1]; or die "$argv[3] (expected '$argv[2]')"
end

set -l jwt (python3 -c '
import base64, json
b = lambda o: base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
claims = {"email": "work@example.com", "https://api.openai.com/auth": {
    "chatgpt_plan_type": "pro", "chatgpt_subscription_active_until": "2030-01-02T00:00:00+00:00"}}
print(b({"alg": "none"}) + "." + b(claims) + ".sig")')
mkdir -p $HOME/.codex-work
printf '{"tokens":{"id_token":"%s"}}' $jwt > $HOME/.codex-work/auth.json

source $root/codex-switch.fish

set -l out (cx ls | string collect)
contains_str $out work@example.com "discovers signed-in home"
contains_str $out 2030-01-02 "expiry column"
ok "first run + ls"

contains_str (cx version | string collect) "CodeX Switch" version
ok version

set -l side $tmp/side-home
mkdir $side
cx add side --no-login --home $side >/dev/null
contains_str (cx ls | string collect) side "add registers"
cx add side 2>/dev/null; and die "duplicate add should fail"
cx use side >/dev/null
test "$CODEX_HOME" = "$side"; or die "use did not set CODEX_HOME ($CODEX_HOME)"
test "$CX_PROMPT_TEXT" = "[codex:side]"; or die "prompt text: $CX_PROMPT_TEXT"
cx use - >/dev/null
test -z "$CODEX_HOME"; or die "use - did not clear"
ok "add / use / prompt marker"

set -l proj $tmp/proj/sub/deeper
mkdir -p $proj
cd $tmp/proj
cx bind side >/dev/null
test "$CODEX_HOME" = "$side"; or die "bind did not apply"
cd $HOME
test -z "$CODEX_HOME"; or die "leaving bound dir did not restore ($CODEX_HOME)"
cd $proj
test "$CODEX_HOME" = "$side"; or die "entering subdir did not switch"
test "$CX_AUTO_ACTIVE" = side; or die "auto state"
cd $HOME
begin
    test -z "$CODEX_HOME"; and test -z "$CX_AUTO_ACTIVE"
end; or die "state not cleared on leave"
ok "bind + cd hook"

cx rm side </dev/null >/dev/null
test -d $side; or die "rm without --purge must keep data"
cx add side --no-login --home $side >/dev/null
cx rm side --purge >/dev/null
test -d $side; and die "--purge must delete"
ok "rm / --purge"

mkdir $tmp/bin
printf '#!/bin/sh\necho "FAKE_HOME=$CODEX_HOME"\necho "ARGS=$*"\n' > $tmp/bin/codex
chmod +x $tmp/bin/codex
set -l one (begin; set -lx PATH $tmp/bin $PATH; fish -c "source $root/codex-switch.fish; cx work hello-world"; end | string collect)
contains_str $one "FAKE_HOME=$HOME/.codex-work" "one-shot home"
contains_str $one "ARGS=hello-world" "one-shot args"
ok one-shot

rm -rf $tmp
echo "All $n fish smoke checks passed."
