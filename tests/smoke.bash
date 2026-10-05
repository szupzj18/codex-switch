#!/usr/bin/env bash
# CodeX Switch smoke test for the bash wrapper — runs inside a temporary HOME.
#
#   bash tests/smoke.bash
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config"
unset CODEX_HOME CX_AUTO_ACTIVE
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

mkdir -p "$HOME/.codex-adopt"
printf '{"tokens":{"id_token":"%s"}}' "$(mkjwt adopt@example.com)" > "$HOME/.codex-adopt/auth.json"
out=$(printf 'y\nn\nn\nn\n' | PATH="$TMP/bin:$PATH" cx setup 2>&1)
contains "$out" "CodeX Switch setup" "setup banner"
contains "$(cat "$XDG_CONFIG_HOME/codex-switch/accounts.tsv")" "adopt" "setup registers"
cx setup </dev/null >/dev/null 2>&1 || die "setup must survive EOF"
ok "setup wizard"

echo "All $n bash smoke checks passed."
