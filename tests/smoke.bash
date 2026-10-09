#!/usr/bin/env bash
# Zorua smoke test for the bash wrapper — runs inside a temporary HOME.
#
#   bash tests/smoke.bash
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config"
unset CODEX_HOME ZORUA_AUTO_ACTIVE CLAUDE_CONFIG_DIR ZORUA_AUTO_CLAUDE ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
mkdir -p "$HOME"

n=0
ok() { n=$((n + 1)); echo "ok $1"; }
die() { echo "FAIL $1" >&2; exit 1; }
contains() { printf '%s' "$1" | grep -Fq -- "$2" || die "$3 (expected '$2' in: $1)"; }
not_contains() { ! printf '%s' "$1" | grep -Fq -- "$2" || die "$3 (unexpected '$2' in: $1)"; }

mkjwt() {
  python3 - "$1" <<'PY'
import base64, json, sys
b = lambda o: base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
claims = {"email": sys.argv[1], "https://api.openai.com/auth": {
    "chatgpt_plan_type": "pro", "chatgpt_subscription_active_until": "2030-01-02T00:00:00+00:00"}}
print(b({"alg": "none"}) + "." + b(claims) + ".sig")
PY
}

mkdir -p "$HOME/.codex-work"
printf '{"tokens":{"id_token":"%s"}}' "$(mkjwt work@example.com)" > "$HOME/.codex-work/auth.json"

# bash is non-interactive here, so install the hook by hand afterwards
source "$ROOT/zorua.bash"

out=$(zorua ls)
contains "$out" "work@example.com" "discovers signed-in home"
contains "$out" "pro" "plan column"
not_contains "$out" "2030-01-02" "expiry hidden by default"
contains "$(zorua ls --expiry)" "2030-01-02" "expiry column on request"
not_contains "$out" $'\033' "no colors when piped"
contains "$(zorua ls -v)" "~/.codex-work" "verbose view"
not_contains "$out" "Claude Code" "no section headings while only codex accounts exist"
ok "first run + ls"

contains "$(zorua version)" "Zorua" "version"
ok "version"

SIDE="$TMP/side-home"; mkdir "$SIDE"
zorua add side --no-login --home "$SIDE" >/dev/null
contains "$(zorua ls)" "side" "add registers"
if zorua add side 2>/dev/null; then die "duplicate add should fail"; fi
if zorua add "bad name" 2>/dev/null; then die "bad name should fail"; fi
zorua use side >/dev/null
[ "$CODEX_HOME" = "$SIDE" ] || die "use did not set CODEX_HOME"
[ "$ZORUA_PROMPT_TEXT" = "[codex:side]" ] || die "prompt text: $ZORUA_PROMPT_TEXT"
contains "$(zorua prompt)" "[codex:side]" "zorua prompt"
zorua use - >/dev/null
[ -z "${CODEX_HOME:-}" ] || die "use - did not clear"
[ -z "$ZORUA_PROMPT_TEXT" ] || die "prompt text not cleared"
ok "add / use / prompt marker"

PROJ="$TMP/proj/sub/deeper"; mkdir -p "$PROJ"
cd "$TMP/proj"
zorua bind side >/dev/null
[ "$CODEX_HOME" = "$SIDE" ] || die "bind did not apply"
[ "$ZORUA_PROMPT_TEXT" = "[codex:side:auto]" ] || die "auto marker: $ZORUA_PROMPT_TEXT"
cd "$HOME"; _zorua_prompt_hook
[ -z "${CODEX_HOME:-}" ] || die "leaving bound dir did not restore"
cd "$PROJ"; _zorua_prompt_hook
[ "$CODEX_HOME" = "$SIDE" ] || die "entering subdir did not switch"
[ "$ZORUA_AUTO_ACTIVE" = side ] || die "auto state"
cd "$HOME"; _zorua_prompt_hook
[ -z "${CODEX_HOME:-}" ] && [ -z "$ZORUA_AUTO_ACTIVE" ] || die "state not cleared on leave"
ok "bind + cd hook"

cd "$PROJ"; _zorua_prompt_hook
contains "$(zorua binds)" "$TMP/proj" "binds lists path"
zorua unbind "$TMP/proj" >/dev/null
[ -z "${CODEX_HOME:-}" ] || die "unbind did not restore"
cd "$HOME"
ok "binds / unbind"

zorua rm side </dev/null >/dev/null
[ -d "$SIDE" ] || die "rm without --purge must keep data"
zorua add side --no-login --home "$SIDE" >/dev/null
zorua rm side --purge >/dev/null
[ ! -d "$SIDE" ] || die "--purge must delete"
if zorua rm default 2>/dev/null; then die "default is protected"; fi
ok "rm / --purge / default protected"

mkdir "$TMP/bin"
printf '#!/bin/sh\necho "FAKE_HOME=$CODEX_HOME"\necho "KEY=${ZORUA_CODEX_KEY:-unset}"\necho "ARGS=$*"\n' > "$TMP/bin/codex"; chmod +x "$TMP/bin/codex"
out=$(PATH="$TMP/bin:$PATH" zorua work hello-world)
contains "$out" "FAKE_HOME=$HOME/.codex-work" "one-shot home"
contains "$out" "ARGS=hello-world" "one-shot args"
ok "one-shot"


# ---- Claude Code accounts (phase 1: subscription logins) -------------------

mkdir -p "$TMP/cbin"
cp "$ROOT/tests/fake-claude" "$TMP/cbin/claude"
OLDPATH=$PATH
export PATH="$TMP/cbin:$PATH"

zorua add --claude alt >/dev/null
[ -f "$XDG_CONFIG_HOME/zorua/claude-accounts.tsv" ] || die "claude registry not written"
out=$(zorua ls)
contains "$out" "claude@example.com" "claude account email from claude auth status"
contains "$out" "max" "claude plan"
contains "$out" "Claude Code" "claude accounts get their own section"
contains "$out" "Codex" "codex accounts get their own section"
if zorua add --claude work 2>/dev/null; then die "name clash across kinds must fail"; fi
if zorua add --claude x --device-auth 2>/dev/null; then die "--device-auth is codex-only"; fi
ok "add --claude + ls (shared namespace)"

ALT="$HOME/.claude-alt"
warn=$(ANTHROPIC_AUTH_TOKEN=secret zorua use alt 2>&1 >/dev/null) || true
contains "$warn" "ANTHROPIC_AUTH_TOKEN" "override warning"
zorua use alt >/dev/null
[ "$CLAUDE_CONFIG_DIR" = "$ALT" ] || die "use did not set CLAUDE_CONFIG_DIR"
[ -z "${CODEX_HOME:-}" ] || die "claude use must not touch CODEX_HOME"
[ "$ZORUA_PROMPT_TEXT" = "[claude:alt]" ] || die "prompt: $ZORUA_PROMPT_TEXT"
zorua use work >/dev/null
[ "$ZORUA_PROMPT_TEXT" = "[codex:work claude:alt]" ] || die "combined prompt: $ZORUA_PROMPT_TEXT"
zorua use - >/dev/null
[ -z "${CODEX_HOME:-}" ] && [ -z "${CLAUDE_CONFIG_DIR:-}" ] || die "use - must clear both"
ok "use (claude) + combined prompt + override warning"

out=$(ANTHROPIC_AUTH_TOKEN=secret ANTHROPIC_BASE_URL=http://127.0.0.1:1 zorua alt hello)
contains "$out" "FAKE_CLAUDE_DIR=$ALT" "one-shot claude dir"
contains "$out" "TOKEN=unset" "one-shot strips ANTHROPIC_AUTH_TOKEN"
contains "$out" "BASE=https://api.anthropic.com" "one-shot pins the official base url"
contains "$out" "ARGS=hello" "one-shot args"
ok "claude one-shot cleans overrides"

cd "$TMP/proj"
zorua bind alt >/dev/null
[ "$CLAUDE_CONFIG_DIR" = "$ALT" ] || die "claude bind did not apply"
zorua bind work >/dev/null
[ "$CODEX_HOME" = "$HOME/.codex-work" ] || die "codex bind in same dir must coexist"
[ "$ZORUA_PROMPT_TEXT" = "[codex:work:auto claude:alt:auto]" ] || die "auto prompt: $ZORUA_PROMPT_TEXT"
cd "$HOME"; _zorua_prompt_hook
[ -z "${CLAUDE_CONFIG_DIR:-}" ] && [ -z "${CODEX_HOME:-}" ] || die "leaving must restore both"
cd "$TMP/proj"; _zorua_prompt_hook
[ "$CLAUDE_CONFIG_DIR" = "$ALT" ] || die "re-entering must switch claude again"
zorua unbind "$TMP/proj" >/dev/null
[ -z "${CLAUDE_CONFIG_DIR:-}" ] || die "unbind must restore"
cd "$HOME"
ok "claude + codex bindings coexist"

zorua rm alt --purge >/dev/null
[ ! -d "$ALT" ] || die "purge must delete claude home"
not_contains "$(zorua ls)" "claude@example.com" "rm unregisters claude account"
export PATH=$OLDPATH
ok "rm claude account"


# ---- Claude usage via the status-line relay --------------------------------

export PATH="$TMP/cbin:$PATH"
zorua add --claude u1 >/dev/null
U1="$HOME/.claude-u1"
out=$(zorua usage)
contains "$out" "no Claude usage yet" "hint when no cache exists"
# the relay: caches rate_limits, passes stdin/stdout through to the wrapped command
NOW=$(date +%s)
JSON="{\"model\":{\"display_name\":\"X\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":$((NOW + 3600))},\"seven_day\":{\"used_percentage\":7.4,\"resets_at\":$((NOW + 200000))}}}"
echo "$JSON" | CLAUDE_CONFIG_DIR="$U1" python3 "$ROOT/zorua_statusline.py" -- 'cat | python3 -c "import sys,json;print(\"WRAPPED:\" + json.load(sys.stdin)[\"model\"][\"display_name\"])"' > "$TMP/relay.out"
contains "$(cat "$TMP/relay.out")" "WRAPPED:X" "relay passes stdin through and returns the wrapped output"
[ -f "$U1/.zorua-usage.json" ] || die "relay did not write the cache"
out=$(zorua usage)
contains "$out" " 42%" "5h used percent from cache"
contains "$out" "  7%" "7d used percent from cache"
contains "$out" "Claude usage as of" "age note"
ok "claude usage from the status-line relay cache"

# hook install / status / remove on a settings.json with an existing status line
printf '{"statusLine":{"type":"command","command":"echo hi","padding":0},"theme":"dark"}' > "$U1/settings.json"
out=$(zorua hook install u1 --dry-run)
contains "$out" "dry run" "dry run"
contains "$(cat "$U1/settings.json")" '"echo hi"' "dry run must not write"
zorua hook install u1 >/dev/null
contains "$(cat "$U1/settings.json")" "zorua_statusline.py" "relay installed in settings"
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert d['theme']=='dark' and d['statusLine']['padding']==0, d" "$U1/settings.json" || die "other settings must be preserved"
contains "$(zorua hook status u1)" "installed" "status"
contains "$(zorua hook install u1)" "already installed" "idempotent"
ls "$U1"/settings.json.zorua-bak-* >/dev/null 2>&1 || die "backup missing"
echo "$JSON" | CLAUDE_CONFIG_DIR="$U1" bash -c "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['statusLine']['command'])" "$U1/settings.json")" | grep -q '^hi$' || die "installed command must still run the original"
zorua hook remove u1 >/dev/null
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert d['statusLine']['command']=='echo hi', d" "$U1/settings.json" || die "remove must restore the original command"
if zorua hook install work 2>/dev/null; then die "hook only for claude accounts"; fi
zorua rm u1 --purge >/dev/null

# account WITHOUT a status line: explicit confirmation, minimal default line, clean removal
zorua add --claude u2 >/dev/null
U2="$HOME/.claude-u2"
echo '{"theme":"dark"}' > "$U2/settings.json"
out=$(zorua hook install u2 --dry-run)
contains "$out" "hides most footer keyboard hints" "no-statusline notice"
if zorua hook install u2 </dev/null >/dev/null 2>&1; then die "must refuse without --yes when not on a tty"; fi
not_contains "$(cat "$U2/settings.json")" "zorua_statusline" "refused install must not write"
zorua hook install u2 --yes >/dev/null
line=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":8},\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":$((NOW + 3600))}}}" | CLAUDE_CONFIG_DIR="$U2" bash -c "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['statusLine']['command'])" "$U2/settings.json")")
[ "$line" = "Opus · ctx 8% · 5h 42%" ] || die "default status line: $line"
zorua hook remove u2 >/dev/null
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert 'statusLine' not in d and d['theme']=='dark', d" "$U2/settings.json" || die "remove must delete the status line we added"
zorua rm u2 --purge >/dev/null

# portable + self-healing relay command, legacy format, remove --all
INST="$HOME/.zoruainst"; mkdir -p "$INST"
cp "$ROOT/zorua_core.py" "$ROOT/zorua_providers.py" "$ROOT/zorua_statusline.py" "$INST/"
zorua add --claude u3 >/dev/null
U3="$HOME/.claude-u3"
printf '{"statusLine":{"type":"command","command":"cat >/dev/null; echo orig-line"}}' > "$U3/settings.json"
python3 "$INST/zorua_core.py" hook install u3 >/dev/null
cmd=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['statusLine']['command'])" "$U3/settings.json")
contains "$cmd" '"$HOME/.zoruainst/zorua_statusline.py"' "script path is written as \$HOME-relative"
not_contains "$cmd" "$HOME" "no absolute home directory in the command"
[ "$(echo '{}' | sh -c "$cmd")" = "orig-line" ] || die "relay run must still print the original output"
rm "$INST/zorua_statusline.py"
[ "$(echo '{}' | sh -c "$cmd")" = "orig-line" ] || die "missing relay must fall back to the original command"
cp "$ROOT/zorua_statusline.py" "$INST/"
# a settings.json written by 0.3.1 (python3 <abs script> -- <orig>) is recognised and upgraded
printf '{"statusLine":{"type":"command","command":"python3 %s -- %s"}}' "$INST/zorua_statusline.py" "'cat >/dev/null; echo orig-line'" > "$U3/settings.json"
contains "$(python3 "$INST/zorua_core.py" hook status u3)" "installed" "legacy command recognised"
contains "$(python3 "$INST/zorua_core.py" hook install u3)" "updating the relay command" "legacy command upgraded"
contains "$(python3 "$INST/zorua_core.py" hook status)" "[u3]" "status lists all Claude accounts"
python3 "$INST/zorua_core.py" hook remove --all >/dev/null
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert d['statusLine']['command']=='cat >/dev/null; echo orig-line', d" "$U3/settings.json" || die "remove --all must restore the original command"
zorua rm u3 --purge >/dev/null
rm -rf "$INST"

# uninstall.sh: note without --purge, restore with --purge
INST="$HOME/.zorua"; mkdir -p "$INST"
cp "$ROOT/zorua_core.py" "$ROOT/zorua_providers.py" "$ROOT/zorua_statusline.py" "$INST/"
zorua add --claude u4 >/dev/null
U4="$HOME/.claude-u4"
printf '{"statusLine":{"type":"command","command":"echo keep-me"}}' > "$U4/settings.json"
python3 "$INST/zorua_core.py" hook install u4 >/dev/null
out=$(sh "$ROOT/uninstall.sh" 2>&1)
contains "$out" "still use the usage relay" "uninstall without --purge warns about active relays"
[ -d "$INST" ] || die "uninstall without --purge must keep the files"
sh "$ROOT/uninstall.sh" --purge >/dev/null 2>&1
[ ! -d "$INST" ] || die "--purge must delete the install dir"
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert d['statusLine']['command']=='echo keep-me', d" "$U4/settings.json" || die "--purge must restore the original status line first"
zorua rm u4 --purge >/dev/null

# pre-rename relay command / cache file names (0.4.0: cx_statusline.py, __cx_orig, .cx-usage.json) still work
zorua add --claude u5 >/dev/null
U5="$HOME/.claude-u5"
OLDCMD='__cx_orig='"'"'echo old-orig'"'"'; if [ -f "$HOME/.zorua/cx_statusline.py" ] && command -v python3 >/dev/null 2>&1; then python3 "$HOME/.zorua/cx_statusline.py" -- "$__cx_orig"; else sh -c "$__cx_orig"; fi'
python3 -c "import json,sys;json.dump({'statusLine':{'type':'command','command':sys.argv[2]}},open(sys.argv[1],'w'))" "$U5/settings.json" "$OLDCMD"
contains "$(zorua hook status u5)" "installed" "0.4.0-format relay recognised"
contains "$(zorua hook install u5)" "updating the relay command" "0.4.0-format relay upgraded"
cmd=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['statusLine']['command'])" "$U5/settings.json")
contains "$cmd" "zorua_statusline.py" "upgraded command uses the new script name"
not_contains "$cmd" "cx_" "no cx names left in the upgraded command"
zorua hook remove u5 >/dev/null
python3 -c "import json,sys;assert json.load(open(sys.argv[1]))['statusLine']['command']=='echo old-orig'" "$U5/settings.json" || die "remove must restore the original from the old format"
NOW2=$(date +%s)
echo "{\"five_hour\":{\"used_percentage\":33,\"resets_at\":$((NOW2 + 3000))},\"updated_at\":$NOW2}" > "$U5/.cx-usage.json"
contains "$(zorua usage)" " 33%" "legacy cache file name is still read"
zorua rm u5 --purge >/dev/null
export PATH=$OLDPATH
ok "hook install / remove restores the original status line"


# ---- migration from the old codex-switch name --------------------------------
OLDCFG="$TMP/mig/config"; mkdir -p "$OLDCFG/codex-switch" "$TMP/mig/home/.codex-legacy"
printf 'default\t%s\nlegacy\t%s\n' "$TMP/mig/home/.codex" "$TMP/mig/home/.codex-legacy" > "$OLDCFG/codex-switch/accounts.tsv"
printf 'legacy\t%s\n' "$TMP/mig/proj" > "$OLDCFG/codex-switch/bindings.tsv"
out=$(HOME="$TMP/mig/home" XDG_CONFIG_HOME="$OLDCFG" python3 "$ROOT/zorua_core.py" ls)
contains "$out" "legacy" "accounts carried over from the old config dir"
[ -f "$OLDCFG/zorua/bindings.tsv" ] || die "bindings not carried over"
[ -f "$OLDCFG/codex-switch/accounts.tsv" ] || die "old config must be kept as a backup"
ok "registry migrated from ~/.config/codex-switch"

mkdir -p "$HOME/.codex-adopt"
printf '{"tokens":{"id_token":"%s"}}' "$(mkjwt adopt@example.com)" > "$HOME/.codex-adopt/auth.json"
out=$(printf 'y\nn\nn\nn\n' | PATH="$TMP/bin:$PATH" zorua setup 2>&1)
contains "$out" "Zorua setup" "setup banner"
contains "$(cat "$XDG_CONFIG_HOME/zorua/accounts.tsv")" "adopt" "setup registers"
zorua setup </dev/null >/dev/null 2>&1 || die "setup must survive EOF"
ok "setup wizard"

# ---- providers ----------------------------------------------------------------

fails() { if "$@" >/dev/null 2>&1; then die "expected failure: $*"; fi; }
mkdir -p "$HOME/.claude"
echo '{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:1","ANTHROPIC_AUTH_TOKEN":"PROXY_MANAGED","ANTHROPIC_DEFAULT_SONNET_MODEL":"internal","CLAUDE_CODE_MAX_OUTPUT_TOKENS":"64000"},"permissions":{"deny":["Bash(rm:*)"]}}' > "$HOME/.claude/settings.json"
out=$(zorua provider add glm --base-url https://api.example.com/anthropic/ --key sk-glm-secret-123456 --model sonnet=glm-4.6)
contains "$out" "added claude provider: glm" "provider add"
echo sk-kimi-secret-123456 | zorua provider add kimi --base-url https://kimi.example.com --api-key --model default=k3 >/dev/null
fails zorua provider add glm --base-url https://x.example.com --key k
fails zorua provider add ls --base-url https://x.example.com --key k
fails zorua provider add bad --base-url ftp://x.example.com --key k
fails zorua provider add bad --base-url https://x.example.com --key k --model nope=x
[ "$(stat -c %a "$XDG_CONFIG_HOME/zorua/providers.json" 2>/dev/null || stat -f %Lp "$XDG_CONFIG_HOME/zorua/providers.json")" = 600 ] || die "providers.json must be 0600"
out="$(zorua provider ls)$(zorua provider show glm)$(zorua)"
not_contains "$out" "sk-glm-secret-123456" "keys are masked in ls/show/list"
contains "$out" "api.example.com" "provider endpoint shown"
zorua use glm >/dev/null
[ "$ZORUA_CLAUDE_PROVIDER" = glm ] || die "use glm did not set ZORUA_CLAUDE_PROVIDER"
[ "$ZORUA_PROMPT_TEXT" = "[claude-provider:glm]" ] || die "provider marker: $ZORUA_PROMPT_TEXT"
out=$(PATH="$TMP/cbin:$PATH" claude hi)
contains "$out" "TOKEN=sk-glm-secret-123456" "provider key reaches claude"
contains "$out" "BASE=https://api.example.com/anthropic" "provider base url reaches claude"
contains "$out" "ARGS=--settings" "claude is launched with --settings"
contains "$out" "SETTINGS_PERMS=600" "settings file is private"
contains "$out" '"ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-4.6"' "provider model beats settings.json"
zorua use kimi >/dev/null
out=$(PATH="$TMP/cbin:$PATH" claude hi)
contains "$out" '"ANTHROPIC_API_KEY": "sk-kimi-secret-123456"' "api-key style provider"
contains "$out" '"ANTHROPIC_AUTH_TOKEN": ""' "conflicting token from settings.json is blanked"
contains "$out" '"ANTHROPIC_DEFAULT_SONNET_MODEL": ""' "conflicting model from settings.json is blanked"
# only provider-related keys are overridden: the generated settings hold nothing but an env block,
# and unrelated user variables are neither copied nor blanked
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert list(d)==["env"], list(d)' "$XDG_CONFIG_HOME/zorua/run/kimi.settings.json" || die "generated settings must only contain env"
not_contains "$(cat "$XDG_CONFIG_HOME/zorua/run/kimi.settings.json")" "MAX_OUTPUT_TOKENS" "unrelated user env is left alone"
out=$(PATH="$TMP/cbin:$PATH" zorua glm oneshot)
contains "$out" "ARGS=--settings" "one-shot provider launch"
contains "$out" "oneshot" "one-shot passes arguments"
zorua use - >/dev/null
[ -z "${ZORUA_CLAUDE_PROVIDER:-}" ] || die "use - did not clear ZORUA_CLAUDE_PROVIDER"
out=$(PATH="$TMP/cbin:$PATH" claude plain)
not_contains "$out" "--settings" "claude is untouched without a provider"
mkdir -p "$TMP/pproj"; cd "$TMP/pproj"
zorua bind glm >/dev/null
[ "$ZORUA_CLAUDE_PROVIDER" = glm ] && [ "$ZORUA_AUTO_CLAUDE_PROVIDER" = glm ] || die "provider bind did not apply"
cd "$TMP"; zorua apply "$PWD"
[ -z "${ZORUA_CLAUDE_PROVIDER:-}" ] || die "leaving the bound directory did not restore"
zorua apply "$TMP/pproj"
[ "$ZORUA_CLAUDE_PROVIDER" = glm ] || die "re-entering the bound directory did not switch"
zorua unbind "$TMP/pproj" >/dev/null
zorua use glm >/dev/null
fails zorua provider rm glm
zorua use - >/dev/null
zorua provider rm glm >/dev/null
contains "$(zorua provider ls)" "kimi" "other providers survive rm"
not_contains "$(zorua provider ls)" "glm " "provider rm"
ok "providers: add, use, claude launch, bind, rm"

python3 - "$TMP/ccswitch.db" <<'PY'
import json, sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE providers (id TEXT, app_type TEXT, name TEXT, settings_config TEXT, sort_index INTEGER)")
rows = [
  ("a", "claude", "Super Relay", {"env": {"ANTHROPIC_BASE_URL": "https://relay.example.com", "ANTHROPIC_AUTH_TOKEN": "tok-relay-123456789", "ANTHROPIC_MODEL": "m1"}}),
  ("b", "claude", "Claude Official", {"env": {}}),
  ("c", "claude", "Proxied", {"env": {"ANTHROPIC_BASE_URL": "http://127.0.0.1:15721", "ANTHROPIC_AUTH_TOKEN": "PROXY_MANAGED"}}),
  ("g", "claude", "DeepSeek", {"env": {"ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic", "ANTHROPIC_AUTH_TOKEN": "tok-dsc-123456789"}}),
  ("e", "codex", "DeepSeek", {"auth": {"OPENAI_API_KEY": "tok-ds-123456789"}, "config": 'model_provider = "custom"\nmodel = "ds-flash"\n\n[model_providers.custom]\nname = "deepseek"\nbase_url = "https://api.deepseek.com"\nwire_api = "responses"\n'}),
  ("f", "codex", "OpenAI Official", {"auth": {"OPENAI_API_KEY": None}, "config": ""}),
  ("d", "pi", "pi-only", {"env": {"ANTHROPIC_BASE_URL": "https://pi.example.com", "ANTHROPIC_AUTH_TOKEN": "tok-pi-123456789"}}),
]
for i, (id_, app, name, cfg) in enumerate(rows):
    con.execute("INSERT INTO providers VALUES (?,?,?,?,?)", (id_, app, name, json.dumps(cfg), i))
con.commit()
PY
out=$(zorua provider import cc-switch --db "$TMP/ccswitch.db" --dry-run)
contains "$out" "super-relay" "import lists the custom claude provider"
contains "$out" "deepseek" "import lists the custom codex provider"
not_contains "$out" "OpenAI" "official codex entry skipped"
not_contains "$out" "tok-ds-123456789" "codex import never prints keys"
not_contains "$out" "Proxied" "proxy-managed entries skipped"
not_contains "$out" "pi-only" "other apps skipped"
not_contains "$out" "tok-relay-123456789" "import never prints keys"
! zorua provider ls | grep -q super-relay || die "dry run must not write"
zorua provider import cc-switch --db "$TMP/ccswitch.db" >/dev/null
contains "$(zorua provider show super-relay)" "ANTHROPIC_MODEL=m1" "imported env is kept"
contains "$(zorua provider show deepseek-codex)" "model=ds-flash" "imported codex provider is kept (renamed on a name clash)"
contains "$(zorua provider show deepseek-codex)" "agent=codex" "imported codex agent"
contains "$(zorua provider show deepseek)" "agent=claude" "the claude provider keeps the plain name"
out=$(zorua provider import cc-switch --db "$TMP/ccswitch.db")
contains "$out" "already exists" "import skips existing names"
ok "providers: import from cc-switch"

# ---- codex providers: one slot per agent ---------------------------------------

echo sk-ds-secret-123456 | zorua provider add ds --codex --base-url https://api.deepseek.com --model deepseek-v4-flash >/dev/null
fails zorua provider add ds2 --codex --base-url https://x.example.com --key k
fails zorua provider add ds2 --codex --api-key --base-url https://x.example.com --model m --key k
out="$(zorua provider ls)$(zorua provider show ds)"
not_contains "$out" "sk-ds-secret-123456" "codex key masked"
contains "$out" "codex" "agent column"
zorua use kimi >/dev/null; zorua use ds >/dev/null
[ "$ZORUA_CODEX_PROVIDER" = ds ] && [ "$ZORUA_CLAUDE_PROVIDER" = kimi ] || die "claude and codex providers must be independent"
contains "$ZORUA_PROMPT_TEXT" "codex-provider:ds" "codex provider marker"
contains "$ZORUA_PROMPT_TEXT" "claude-provider:kimi" "claude provider marker"
out=$(PATH="$TMP/bin:$PATH" codex exec hi)
contains "$out" "KEY=sk-ds-secret-123456" "codex key travels in the environment"
contains "$out" 'model_provider="zorua_ds"' "codex provider selected via -c"
contains "$out" 'base_url="https://api.deepseek.com"' "codex base url via -c"
contains "$out" 'model="deepseek-v4-flash"' "codex model via -c"
not_contains "$(printf %s "$out" | grep '^ARGS=')" "sk-ds-secret" "key must not appear in argv"
[ "$(printf %s "$out" | grep '^ARGS=' | grep -o -- '-c ' | wc -l | tr -d ' ')" = 3 ] || die "codex provider must override exactly model_provider, model_providers.* and model"
contains "$out" "ARGS=-c" "codex flags precede the user's arguments"
out=$(PATH="$TMP/bin:$PATH" zorua ds exec hi)
contains "$out" 'model_provider="zorua_ds"' "one-shot codex provider"
zorua use - >/dev/null
[ -z "${ZORUA_CODEX_PROVIDER:-}" ] && [ -z "${ZORUA_CLAUDE_PROVIDER:-}" ] || die "use - must clear both provider slots"
out=$(PATH="$TMP/bin:$PATH" codex exec hi)
not_contains "$out" "model_provider" "codex untouched without a provider"
not_contains "$out" "KEY=sk-" "no key without a provider"
mkdir -p "$TMP/cproj"; cd "$TMP/cproj"
zorua bind ds >/dev/null
[ "$ZORUA_CODEX_PROVIDER" = ds ] && [ -z "${ZORUA_CLAUDE_PROVIDER:-}" ] || die "codex provider bind should only fill the codex slot"
cd "$TMP"; zorua apply "$PWD"
[ -z "${ZORUA_CODEX_PROVIDER:-}" ] || die "leaving the bound directory did not restore the codex slot"
zorua unbind "$TMP/cproj" >/dev/null
zorua provider rm ds >/dev/null
ok "codex providers: independent slot, env key, -c overrides, bind"

echo "All $n bash smoke checks passed."
