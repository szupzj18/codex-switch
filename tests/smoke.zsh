#!/usr/bin/env zsh
# Zorua smoke test — runs entirely inside a temporary HOME.
# It never touches the real ~/.codex*, Zorua registry, or invokes the real codex.
#
#   zsh tests/smoke.zsh

emulate -L zsh
set -e
setopt pipe_fail

ROOT="${0:A:h:h}"
SCRIPT="$ROOT/zorua.zsh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export ZDOTDIR="$HOME"
export XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$HOME"

n=0
ok() { n=$((n + 1)); print -P -- "%F{green}ok%f $1"; }
die() { print -P -- "%F{red}FAIL%f $1" >&2; exit 1; }
contains() {
  print -rn -- "$1" | grep -Fq -- "$2" || die "$3
expected substring: $2
--- got ---
$1"
}
not_contains() {
  ! print -rn -- "$1" | grep -Fq -- "$2" || die "$3
unexpected substring: $2
--- got ---
$1"
}
fails() { "$@" >/dev/null 2>&1 || return 0; die "expected failure but it succeeded: $*"; }

# ---- 1. Build two signed-in homes before sourcing (first-run discovery) ----

mkjwt() {
  python3 - "$1" <<'PY'
import base64, json, sys
def b64(o):
    return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
print(b64({"alg": "none"}) + "." + b64({"email": sys.argv[1]}) + ".sig")
PY
}

mkdir "$HOME/.codex-work" "$HOME/.codex-3" "$HOME/.codex-bad name"
AUTH_FMT='{"tokens":{"id_token":"%s"}}'
print -f "$AUTH_FMT" "$(mkjwt work@example.com)" > "$HOME/.codex-work/auth.json"
print -f "$AUTH_FMT" "$(mkjwt three@example.com)" > "$HOME/.codex-3/auth.json"
# ~/.codex-bad name has no auth.json AND an invalid account name; skip both ways

# ---- 2. Source under temp HOME: seeds default + discovers work/3 -------------

source "$SCRIPT"
out=$(zorua ls)
contains "$out" "default" "first-run seeding"
contains "$out" "work" "first-run discovery"
contains "$out" "3" "first-run numeric names"
contains "$out" "work@example.com" "JWT email decode"
contains "$out" "three@example.com" "JWT email decode (second account)"
not_contains "$out" "bad name" "invalid names skipped by discovery"
ok "first-run seeds default and discovers valid homes"

python3 - "$HOME/.codex-work/auth.json" <<'PY'
import json, sys, base64
b = lambda o: base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
claims = {"email": "work@example.com", "https://api.openai.com/auth": {
    "chatgpt_plan_type": "pro", "chatgpt_subscription_active_until": "2030-01-02T00:00:00+00:00"}}
json.dump({"tokens": {"id_token": b({"alg": "none"}) + "." + b(claims) + ".sig"}}, open(sys.argv[1], "w"))
PY
out=$(zorua ls)
contains "$out" "pro" "plan decode"
contains "$out" "2030-01-02" "expiry decode"
not_contains "$out" $'\033' "no ANSI colors when not a TTY"
out=$(zorua ls -v)
contains "$out" "~/.codex-work" "verbose view shows home paths"
contains "$out" "exp 2030-01-02" "verbose view shows expiry"
out=$(ZORUA_COLOR=always zorua ls)
contains "$out" $'\033[' "ZORUA_COLOR=always forces colors"
ok "zorua ls shows plan and subscription expiry"

# ---- 3. add / use ------------------------------------------------------------

fails zorua add "bad name"
fails zorua add work
SIDE="$TMP/side-home"
mkdir "$SIDE"
fails zorua add dup --no-login --home "$HOME/.codex-work"   # already registered
zorua add side --no-login --home "$SIDE"
out=$(zorua ls)
contains "$out" "side" "add registers new account"

zorua use side
[[ $CODEX_HOME == $SIDE ]] || die "zorua use side did not set CODEX_HOME"
zorua use -
[[ -z ${CODEX_HOME:-} ]] || die "zorua use - did not clear CODEX_HOME"
ok "zorua add / zorua use works"

# ---- 4. bind in non-interactive shell (direct apply on bind) -----------------

PROJ="$TMP/proj/sub/deeper"
mkdir -p "$PROJ"
cd "$TMP/proj"
zorua bind side
[[ $CODEX_HOME == $SIDE ]] || die "bind did not apply immediately"
print -rn -- "$RPROMPT" | grep -q "codex:side:auto" || die "auto marker missing: $RPROMPT"
ok "bind applies immediately with auto marker"

# ---- 5. chpwd auto-switch tested in a real interactive child shell ----------

cd "$HOME"
child=$(env -u CODEX_HOME ZDOTDIR="$HOME" HOME="$HOME" XDG_CONFIG_HOME="$TMP/config" \
  zsh -ic "
    source '$SCRIPT'
    whence -w _zorua | grep -q function || { echo FAIL_COMPLETION; exit 1 }
    cd '$PROJ'
    [[ \$CODEX_HOME == '$SIDE' ]] || { echo FAIL_ENTER; exit 1 }
    print -rn -- \"\$RPROMPT\" | grep -q 'codex:side:auto' || { echo FAIL_MARKER; exit 1 }
    cd '$TMP/proj'
    [[ \$CODEX_HOME == '$SIDE' ]] || { echo FAIL_PREFIX; exit 1 }
    cd '$HOME'
    [[ -z \${CODEX_HOME:-} ]] || { echo FAIL_LEAVE; exit 1 }
    [[ -z \$ZORUA_AUTO_ACTIVE ]] || { echo FAIL_LEAVE_STATE; exit 1 }
    echo CHPWD_OK
  " 2>&1)
contains "$child" "CHPWD_OK" "interactive chpwd auto-switch
$child"
ok "chpwd switches on cd in, keeps on prefix match, restores on leave"

# ---- 6. binds / unbind -------------------------------------------------------

cd "$PROJ"
out=$(zorua binds)
contains "$out" "side" "binds lists account"
contains "$out" "$TMP/proj" "binds lists path"
zorua unbind "$TMP/proj"
[[ -z ${CODEX_HOME:-} ]] || die "unbind did not restore CODEX_HOME"
ok "binds / unbind works"

# ---- 7. rm keeps data by default, then --purge deletes -----------------------

cd "$HOME"
echo n | zorua rm side >/dev/null
[[ -d $SIDE ]] || die "rm should keep data directory without --purge"
out=$(zorua ls)
not_contains "$out" "side" "rm unregisters"
zorua add side --no-login --home "$SIDE"
zorua rm side --purge
[[ ! -d $SIDE ]] || die "--purge did not delete data directory"
ok "rm keeps data then --purge deletes"
fails zorua rm default
ok "default account is protected"

# ---- 8. one-shot invocation through a fake codex -----------------------------

mkdir "$TMP/bin"
cat > "$TMP/bin/codex" <<'SH'
#!/bin/sh
echo "FAKE_CODEX_HOME=$CODEX_HOME"
echo "ARGS=$*"
SH
chmod +x "$TMP/bin/codex"
out=$(PATH="$TMP/bin:$PATH" zorua work hello-world)
contains "$out" "FAKE_CODEX_HOME=$HOME/.codex-work" "one-shot sets CODEX_HOME"
contains "$out" "ARGS=hello-world" "one-shot forwards arguments"
print -rn -- "$out" | grep -qx "FAKE_CODEX_HOME=$HOME/.codex-work" \
  || die "CODEX_HOME was not the only/expected value
$out"
ok "one-shot zorua <account> invokes codex with correct CODEX_HOME and args"

# ---- 10. setup wizard (scripted answers) --------------------------------------

mkdir -p "$HOME/.codex-adopt"
print -r -- '{"tokens":{"id_token":"x.eyJlbWFpbCI6ImFkb3B0QGV4YW1wbGUuY29tIn0.s"}}' > "$HOME/.codex-adopt/auth.json"
# answers: register adopt=y, sign in default=n, add another=n, show usage=n
out=$(printf 'y\nn\nn\nn\n' | zorua setup 2>&1)
contains "$out" "Zorua setup" "setup banner"
contains "$(<"$XDG_CONFIG_HOME/zorua/accounts.tsv")" "adopt	$HOME/.codex-adopt" "setup registers discovered home"
out=$(zorua setup </dev/null 2>&1) || die "setup must not fail on EOF"
ok "zorua setup adopts existing homes and survives EOF"

# ---- 11. claude account through the zsh wrapper -------------------------------

mkdir -p "$TMP/cbin"
cp "$ROOT/tests/fake-claude" "$TMP/cbin/claude"
PATH="$TMP/cbin:$PATH" zorua add --claude alt >/dev/null
contains "$(PATH="$TMP/cbin:$PATH" zorua ls)" "claude@example.com" "claude account listed"
zorua use alt >/dev/null 2>&1
[[ $CLAUDE_CONFIG_DIR == $HOME/.claude-alt ]] || die "zorua use alt did not set CLAUDE_CONFIG_DIR"
print -rn -- "$RPROMPT" | grep -q "claude:alt" || die "claude marker missing: $RPROMPT"
zorua use - >/dev/null
[[ -z ${CLAUDE_CONFIG_DIR:-} ]] || die "zorua use - did not clear CLAUDE_CONFIG_DIR"
zorua rm alt --purge >/dev/null
ok "claude accounts work through the zsh wrapper"

# ---- 12. providers ---------------------------------------------------------------

mkdir -p "$HOME/.claude"
print -r -- '{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:1","ANTHROPIC_AUTH_TOKEN":"PROXY_MANAGED","ANTHROPIC_DEFAULT_SONNET_MODEL":"internal"}}' > "$HOME/.claude/settings.json"
out=$(zorua provider add glm --base-url https://api.example.com/anthropic/ --key sk-glm-secret-123456 --model sonnet=glm-4.6)
contains "$out" "added provider: glm" "provider add"
echo sk-kimi-secret-123456 | zorua provider add kimi --base-url https://kimi.example.com --api-key --model default=k3 >/dev/null
fails zorua provider add glm --base-url https://x.example.com --key k
fails zorua provider add ls --base-url https://x.example.com --key k
fails zorua provider add bad --base-url ftp://x.example.com --key k
fails zorua provider add bad --base-url https://x.example.com --key k --model nope=x
[[ $(stat -f %Lp "$XDG_CONFIG_HOME/zorua/providers.json" 2>/dev/null || stat -c %a "$XDG_CONFIG_HOME/zorua/providers.json") == 600 ]] || die "providers.json must be 0600"
out="$(zorua provider ls)$(zorua provider show glm)$(zorua)"
not_contains "$out" "sk-glm-secret-123456" "keys are masked in ls/show/list"
contains "$out" "api.example.com" "provider endpoint shown"
zorua use glm >/dev/null
[[ $ZORUA_PROVIDER == glm ]] || die "use glm did not set ZORUA_PROVIDER"
print -rn -- "$RPROMPT" | grep -q "provider:glm" || die "provider marker missing: $RPROMPT"
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
out=$(PATH="$TMP/cbin:$PATH" zorua glm oneshot)
contains "$out" "ARGS=--settings" "one-shot provider launch"
contains "$out" "oneshot" "one-shot passes arguments"
zorua use - >/dev/null
[[ -z ${ZORUA_PROVIDER:-} ]] || die "use - did not clear ZORUA_PROVIDER"
out=$(PATH="$TMP/cbin:$PATH" claude plain)
not_contains "$out" "--settings" "claude is untouched without a provider"
mkdir -p "$TMP/pproj"; cd "$TMP/pproj"
zorua bind glm >/dev/null
[[ $ZORUA_PROVIDER == glm && $ZORUA_AUTO_PROVIDER == glm ]] || die "provider bind did not apply"
cd "$TMP"; zorua apply "$PWD"
[[ -z ${ZORUA_PROVIDER:-} ]] || die "leaving the bound directory did not restore"
zorua apply "$TMP/pproj"
[[ $ZORUA_PROVIDER == glm ]] || die "re-entering the bound directory did not switch"
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
  ("d", "pi", "pi-only", {"env": {"ANTHROPIC_BASE_URL": "https://pi.example.com", "ANTHROPIC_AUTH_TOKEN": "tok-pi-123456789"}}),
]
for i, (id_, app, name, cfg) in enumerate(rows):
    con.execute("INSERT INTO providers VALUES (?,?,?,?,?)", (id_, app, name, json.dumps(cfg), i))
con.commit()
PY
out=$(zorua provider import cc-switch --db "$TMP/ccswitch.db" --dry-run)
contains "$out" "super-relay" "import lists the custom claude provider"
not_contains "$out" "Proxied" "proxy-managed entries skipped"
not_contains "$out" "pi-only" "other apps skipped"
not_contains "$out" "tok-relay-123456789" "import never prints keys"
[[ -z $(zorua provider ls | grep super-relay) ]] || die "dry run must not write"
zorua provider import cc-switch --db "$TMP/ccswitch.db" >/dev/null
contains "$(zorua provider show super-relay)" "ANTHROPIC_MODEL=m1" "imported env is kept"
out=$(zorua provider import cc-switch --db "$TMP/ccswitch.db")
contains "$out" "already exists" "import skips existing names"
ok "providers: import from cc-switch"

# ---- 9. version --------------------------------------------------------------

out=$(zorua version)
contains "$out" "Zorua" "version output"
ok "version command"

print ""
print -P -- "%F{green}All $n smoke checks passed.%f"
