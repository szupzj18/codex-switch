#!/usr/bin/env fish
# Zorua smoke test for the fish wrapper — runs inside a temporary HOME.
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

source $root/zorua.fish

set -l out (zorua ls | string collect)
contains_str $out work@example.com "discovers signed-in home"
contains_str $out 2030-01-02 "expiry column"
ok "first run + ls"

contains_str (zorua version | string collect) "Zorua" version
ok version

set -l side $tmp/side-home
mkdir $side
zorua add side --no-login --home $side >/dev/null
contains_str (zorua ls | string collect) side "add registers"
zorua add side 2>/dev/null; and die "duplicate add should fail"
zorua use side >/dev/null
test "$CODEX_HOME" = "$side"; or die "use did not set CODEX_HOME ($CODEX_HOME)"
test "$ZORUA_PROMPT_TEXT" = "[codex:side]"; or die "prompt text: $ZORUA_PROMPT_TEXT"
zorua use - >/dev/null
test -z "$CODEX_HOME"; or die "use - did not clear"
ok "add / use / prompt marker"

set -l proj $tmp/proj/sub/deeper
mkdir -p $proj
cd $tmp/proj
zorua bind side >/dev/null
test "$CODEX_HOME" = "$side"; or die "bind did not apply"
cd $HOME
test -z "$CODEX_HOME"; or die "leaving bound dir did not restore ($CODEX_HOME)"
cd $proj
test "$CODEX_HOME" = "$side"; or die "entering subdir did not switch"
test "$ZORUA_AUTO_ACTIVE" = side; or die "auto state"
cd $HOME
begin
    test -z "$CODEX_HOME"; and test -z "$ZORUA_AUTO_ACTIVE"
end; or die "state not cleared on leave"
ok "bind + cd hook"

zorua rm side </dev/null >/dev/null
test -d $side; or die "rm without --purge must keep data"
zorua add side --no-login --home $side >/dev/null
zorua rm side --purge >/dev/null
test -d $side; and die "--purge must delete"
ok "rm / --purge"

mkdir $tmp/bin
printf '#!/bin/sh\necho "FAKE_HOME=$CODEX_HOME"\necho "ARGS=$*"\n' > $tmp/bin/codex
chmod +x $tmp/bin/codex
set -l one (begin; set -lx PATH $tmp/bin $PATH; fish -c "source $root/zorua.fish; zorua work hello-world"; end | string collect)
contains_str $one "FAKE_HOME=$HOME/.codex-work" "one-shot home"
contains_str $one "ARGS=hello-world" "one-shot args"
ok one-shot

mkdir $tmp/cbin
cp $root/tests/fake-claude $tmp/cbin/claude
set -l oldpath $PATH
set -gx PATH $tmp/cbin $PATH
zorua add --claude alt >/dev/null; or die "add --claude failed"
contains_str (zorua ls | string collect) claude@example.com "claude account listed"
zorua use alt >/dev/null 2>&1
test "$CLAUDE_CONFIG_DIR" = "$HOME/.claude-alt"; or die "use alt did not set CLAUDE_CONFIG_DIR ($CLAUDE_CONFIG_DIR)"
test "$ZORUA_PROMPT_TEXT" = "[claude:alt]"; or die "prompt text: $ZORUA_PROMPT_TEXT"
zorua use - >/dev/null
test -z "$CLAUDE_CONFIG_DIR"; or die "use - did not clear CLAUDE_CONFIG_DIR"
zorua rm alt --purge >/dev/null
set -gx PATH $oldpath
ok "claude accounts"

# ---- providers ----------------------------------------------------------------
mkdir -p $HOME/.claude
echo '{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:1","ANTHROPIC_AUTH_TOKEN":"PROXY_MANAGED","ANTHROPIC_DEFAULT_SONNET_MODEL":"internal"}}' > $HOME/.claude/settings.json
set -gx PATH $tmp/cbin $PATH
zorua provider add glm --base-url https://api.example.com/anthropic/ --key sk-glm-secret-123456 --model sonnet=glm-4.6 >/dev/null; or die "provider add failed"
echo sk-kimi-secret-123456 | zorua provider add kimi --base-url https://kimi.example.com --api-key --model default=k3 >/dev/null; or die "provider add (stdin key) failed"
zorua provider add glm --base-url https://x.example.com --key k 2>/dev/null; and die "duplicate provider should fail"
zorua provider add ls --base-url https://x.example.com --key k 2>/dev/null; and die "reserved name should fail"
set -l listing (begin; zorua provider ls; zorua provider show glm; zorua; end | string collect)
contains_str $listing api.example.com "provider endpoint shown"
string match -q "*sk-glm-secret-123456*" -- $listing; and die "key leaked in listing"
zorua use glm >/dev/null
test "$ZORUA_PROVIDER" = glm; or die "use glm did not set ZORUA_PROVIDER"
test "$ZORUA_PROMPT_TEXT" = "[provider:glm]"; or die "prompt text: $ZORUA_PROMPT_TEXT"
set -l pout (claude hi | string collect)
contains_str $pout "TOKEN=sk-glm-secret-123456" "provider key reaches claude"
contains_str $pout "BASE=https://api.example.com/anthropic" "provider base url reaches claude"
contains_str $pout "SETTINGS_PERMS=600" "settings file is private"
contains_str $pout '"ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-4.6"' "provider model beats settings.json"
zorua use kimi >/dev/null
set pout (claude hi | string collect)
contains_str $pout '"ANTHROPIC_API_KEY": "sk-kimi-secret-123456"' "api-key style provider"
contains_str $pout '"ANTHROPIC_AUTH_TOKEN": ""' "conflicting token is blanked"
zorua use - >/dev/null
test -z "$ZORUA_PROVIDER"; or die "use - did not clear ZORUA_PROVIDER"
string match -q "*--settings*" -- (claude plain | string collect); and die "claude must be untouched without a provider"
mkdir -p $tmp/pproj
cd $tmp/pproj
zorua bind glm >/dev/null
test "$ZORUA_PROVIDER" = glm -a "$ZORUA_AUTO_PROVIDER" = glm; or die "provider bind did not apply"
cd $tmp
test -z "$ZORUA_PROVIDER"; or die "leaving the bound directory did not restore"
cd $tmp/pproj
test "$ZORUA_PROVIDER" = glm; or die "re-entering the bound directory did not switch"
zorua unbind $tmp/pproj >/dev/null
cd $tmp
zorua use glm >/dev/null
zorua provider rm glm 2>/dev/null; and die "active provider must not be removable"
zorua use - >/dev/null
zorua provider rm glm >/dev/null; or die "provider rm failed"
string match -q "*glm *" -- (zorua provider ls | string collect); and die "provider rm left the entry"
set -gx PATH $oldpath
ok "providers: add, use, claude launch, bind, rm"

rm -rf $tmp
echo "All $n fish smoke checks passed."
