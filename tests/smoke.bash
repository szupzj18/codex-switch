#!/usr/bin/env bash
# CodeX Switch smoke test for the bash wrapper — runs inside a temporary HOME.
#
#   bash tests/smoke.bash
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config"
unset CODEX_HOME CX_AUTO_ACTIVE CLAUDE_CONFIG_DIR CX_AUTO_CLAUDE ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
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
source "$ROOT/codex-switch.bash"

out=$(cx ls)
contains "$out" "work@example.com" "discovers signed-in home"
contains "$out" "pro" "plan column"
contains "$out" "2030-01-02" "expiry column"
not_contains "$out" $'\033' "no colors when piped"
contains "$(cx ls -v)" "~/.codex-work" "verbose view"
not_contains "$out" "Claude Code" "no section headings while only codex accounts exist"
ok "first run + ls"

contains "$(cx version)" "CodeX Switch" "version"
ok "version"

SIDE="$TMP/side-home"; mkdir "$SIDE"
cx add side --no-login --home "$SIDE" >/dev/null
contains "$(cx ls)" "side" "add registers"
if cx add side 2>/dev/null; then die "duplicate add should fail"; fi
if cx add "bad name" 2>/dev/null; then die "bad name should fail"; fi
cx use side >/dev/null
[ "$CODEX_HOME" = "$SIDE" ] || die "use did not set CODEX_HOME"
[ "$CX_PROMPT_TEXT" = "[codex:side]" ] || die "prompt text: $CX_PROMPT_TEXT"
contains "$(cx prompt)" "[codex:side]" "cx prompt"
cx use - >/dev/null
[ -z "${CODEX_HOME:-}" ] || die "use - did not clear"
[ -z "$CX_PROMPT_TEXT" ] || die "prompt text not cleared"
ok "add / use / prompt marker"

PROJ="$TMP/proj/sub/deeper"; mkdir -p "$PROJ"
cd "$TMP/proj"
cx bind side >/dev/null
[ "$CODEX_HOME" = "$SIDE" ] || die "bind did not apply"
[ "$CX_PROMPT_TEXT" = "[codex:side:auto]" ] || die "auto marker: $CX_PROMPT_TEXT"
cd "$HOME"; _cx_prompt_hook
[ -z "${CODEX_HOME:-}" ] || die "leaving bound dir did not restore"
cd "$PROJ"; _cx_prompt_hook
[ "$CODEX_HOME" = "$SIDE" ] || die "entering subdir did not switch"
[ "$CX_AUTO_ACTIVE" = side ] || die "auto state"
cd "$HOME"; _cx_prompt_hook
[ -z "${CODEX_HOME:-}" ] && [ -z "$CX_AUTO_ACTIVE" ] || die "state not cleared on leave"
ok "bind + cd hook"

cd "$PROJ"; _cx_prompt_hook
contains "$(cx binds)" "$TMP/proj" "binds lists path"
cx unbind "$TMP/proj" >/dev/null
[ -z "${CODEX_HOME:-}" ] || die "unbind did not restore"
cd "$HOME"
ok "binds / unbind"

cx rm side </dev/null >/dev/null
[ -d "$SIDE" ] || die "rm without --purge must keep data"
cx add side --no-login --home "$SIDE" >/dev/null
cx rm side --purge >/dev/null
[ ! -d "$SIDE" ] || die "--purge must delete"
if cx rm default 2>/dev/null; then die "default is protected"; fi
ok "rm / --purge / default protected"

mkdir "$TMP/bin"
printf '#!/bin/sh\necho "FAKE_HOME=$CODEX_HOME"\necho "ARGS=$*"\n' > "$TMP/bin/codex"; chmod +x "$TMP/bin/codex"
out=$(PATH="$TMP/bin:$PATH" cx work hello-world)
contains "$out" "FAKE_HOME=$HOME/.codex-work" "one-shot home"
contains "$out" "ARGS=hello-world" "one-shot args"
ok "one-shot"


# ---- Claude Code accounts (phase 1: subscription logins) -------------------

mkdir -p "$TMP/cbin"
cp "$ROOT/tests/fake-claude" "$TMP/cbin/claude"
OLDPATH=$PATH
export PATH="$TMP/cbin:$PATH"

cx add --claude alt >/dev/null
[ -f "$XDG_CONFIG_HOME/codex-switch/claude-accounts.tsv" ] || die "claude registry not written"
out=$(cx ls)
contains "$out" "claude@example.com" "claude account email from claude auth status"
contains "$out" "max" "claude plan"
contains "$out" "Claude Code" "claude accounts get their own section"
contains "$out" "Codex" "codex accounts get their own section"
if cx add --claude work 2>/dev/null; then die "name clash across kinds must fail"; fi
if cx add --claude x --device-auth 2>/dev/null; then die "--device-auth is codex-only"; fi
ok "add --claude + ls (shared namespace)"

ALT="$HOME/.claude-alt"
warn=$(ANTHROPIC_AUTH_TOKEN=secret cx use alt 2>&1 >/dev/null) || true
contains "$warn" "ANTHROPIC_AUTH_TOKEN" "override warning"
cx use alt >/dev/null
[ "$CLAUDE_CONFIG_DIR" = "$ALT" ] || die "use did not set CLAUDE_CONFIG_DIR"
[ -z "${CODEX_HOME:-}" ] || die "claude use must not touch CODEX_HOME"
[ "$CX_PROMPT_TEXT" = "[claude:alt]" ] || die "prompt: $CX_PROMPT_TEXT"
cx use work >/dev/null
[ "$CX_PROMPT_TEXT" = "[codex:work claude:alt]" ] || die "combined prompt: $CX_PROMPT_TEXT"
cx use - >/dev/null
[ -z "${CODEX_HOME:-}" ] && [ -z "${CLAUDE_CONFIG_DIR:-}" ] || die "use - must clear both"
ok "use (claude) + combined prompt + override warning"

out=$(ANTHROPIC_AUTH_TOKEN=secret ANTHROPIC_BASE_URL=http://127.0.0.1:1 cx alt hello)
contains "$out" "FAKE_CLAUDE_DIR=$ALT" "one-shot claude dir"
contains "$out" "TOKEN=unset" "one-shot strips ANTHROPIC_AUTH_TOKEN"
contains "$out" "BASE=https://api.anthropic.com" "one-shot pins the official base url"
contains "$out" "ARGS=hello" "one-shot args"
ok "claude one-shot cleans overrides"

cd "$TMP/proj"
cx bind alt >/dev/null
[ "$CLAUDE_CONFIG_DIR" = "$ALT" ] || die "claude bind did not apply"
cx bind work >/dev/null
[ "$CODEX_HOME" = "$HOME/.codex-work" ] || die "codex bind in same dir must coexist"
[ "$CX_PROMPT_TEXT" = "[codex:work:auto claude:alt:auto]" ] || die "auto prompt: $CX_PROMPT_TEXT"
cd "$HOME"; _cx_prompt_hook
[ -z "${CLAUDE_CONFIG_DIR:-}" ] && [ -z "${CODEX_HOME:-}" ] || die "leaving must restore both"
cd "$TMP/proj"; _cx_prompt_hook
[ "$CLAUDE_CONFIG_DIR" = "$ALT" ] || die "re-entering must switch claude again"
cx unbind "$TMP/proj" >/dev/null
[ -z "${CLAUDE_CONFIG_DIR:-}" ] || die "unbind must restore"
cd "$HOME"
ok "claude + codex bindings coexist"

cx rm alt --purge >/dev/null
[ ! -d "$ALT" ] || die "purge must delete claude home"
not_contains "$(cx ls)" "claude@example.com" "rm unregisters claude account"
export PATH=$OLDPATH
ok "rm claude account"


# ---- Claude usage via the status-line relay --------------------------------

export PATH="$TMP/cbin:$PATH"
cx add --claude u1 >/dev/null
U1="$HOME/.claude-u1"
out=$(cx usage)
contains "$out" "no Claude usage yet" "hint when no cache exists"
# the relay: caches rate_limits, passes stdin/stdout through to the wrapped command
NOW=$(date +%s)
JSON="{\"model\":{\"display_name\":\"X\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":$((NOW + 3600))},\"seven_day\":{\"used_percentage\":7.4,\"resets_at\":$((NOW + 200000))}}}"
echo "$JSON" | CLAUDE_CONFIG_DIR="$U1" python3 "$ROOT/cx_statusline.py" -- 'cat | python3 -c "import sys,json;print(\"WRAPPED:\" + json.load(sys.stdin)[\"model\"][\"display_name\"])"' > "$TMP/relay.out"
contains "$(cat "$TMP/relay.out")" "WRAPPED:X" "relay passes stdin through and returns the wrapped output"
[ -f "$U1/.cx-usage.json" ] || die "relay did not write the cache"
out=$(cx usage)
contains "$out" " 42%" "5h used percent from cache"
contains "$out" "  7%" "7d used percent from cache"
contains "$out" "Claude usage as of" "age note"
ok "claude usage from the status-line relay cache"

# hook install / status / remove on a settings.json with an existing status line
printf '{"statusLine":{"type":"command","command":"echo hi","padding":0},"theme":"dark"}' > "$U1/settings.json"
out=$(cx hook install u1 --dry-run)
contains "$out" "dry run" "dry run"
contains "$(cat "$U1/settings.json")" '"echo hi"' "dry run must not write"
cx hook install u1 >/dev/null
contains "$(cat "$U1/settings.json")" "cx_statusline.py" "relay installed in settings"
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert d['theme']=='dark' and d['statusLine']['padding']==0, d" "$U1/settings.json" || die "other settings must be preserved"
contains "$(cx hook status u1)" "installed" "status"
contains "$(cx hook install u1)" "already installed" "idempotent"
ls "$U1"/settings.json.cx-bak-* >/dev/null 2>&1 || die "backup missing"
echo "$JSON" | CLAUDE_CONFIG_DIR="$U1" bash -c "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['statusLine']['command'])" "$U1/settings.json")" | grep -q '^hi$' || die "installed command must still run the original"
cx hook remove u1 >/dev/null
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert d['statusLine']['command']=='echo hi', d" "$U1/settings.json" || die "remove must restore the original command"
if cx hook install work 2>/dev/null; then die "hook only for claude accounts"; fi
cx rm u1 --purge >/dev/null

# account WITHOUT a status line: explicit confirmation, minimal default line, clean removal
cx add --claude u2 >/dev/null
U2="$HOME/.claude-u2"
echo '{"theme":"dark"}' > "$U2/settings.json"
out=$(cx hook install u2 --dry-run)
contains "$out" "hides most footer keyboard hints" "no-statusline notice"
if cx hook install u2 </dev/null >/dev/null 2>&1; then die "must refuse without --yes when not on a tty"; fi
not_contains "$(cat "$U2/settings.json")" "cx_statusline" "refused install must not write"
cx hook install u2 --yes >/dev/null
line=$(echo "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":8},\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":$((NOW + 3600))}}}" | CLAUDE_CONFIG_DIR="$U2" bash -c "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['statusLine']['command'])" "$U2/settings.json")")
[ "$line" = "Opus · ctx 8% · 5h 42%" ] || die "default status line: $line"
cx hook remove u2 >/dev/null
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert 'statusLine' not in d and d['theme']=='dark', d" "$U2/settings.json" || die "remove must delete the status line we added"
cx rm u2 --purge >/dev/null
export PATH=$OLDPATH
ok "hook install / remove restores the original status line"

mkdir -p "$HOME/.codex-adopt"
printf '{"tokens":{"id_token":"%s"}}' "$(mkjwt adopt@example.com)" > "$HOME/.codex-adopt/auth.json"
out=$(printf 'y\nn\nn\nn\n' | PATH="$TMP/bin:$PATH" cx setup 2>&1)
contains "$out" "CodeX Switch setup" "setup banner"
contains "$(cat "$XDG_CONFIG_HOME/codex-switch/accounts.tsv")" "adopt" "setup registers"
cx setup </dev/null >/dev/null 2>&1 || die "setup must survive EOF"
ok "setup wizard"

echo "All $n bash smoke checks passed."
