#!/usr/bin/env zsh
# CodeX Switch smoke test — runs entirely inside a temporary HOME.
# It never touches the real ~/.codex*, CX registry, or invokes the real codex.
#
#   zsh tests/smoke.zsh

emulate -L zsh
set -e
setopt pipe_fail

ROOT="${0:A:h:h}"
SCRIPT="$ROOT/codex-switch.zsh"

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
out=$(cx ls)
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
out=$(cx ls)
contains "$out" "pro" "plan decode"
contains "$out" "2030-01-02" "expiry decode"
not_contains "$out" $'\033' "no ANSI colors when not a TTY"
out=$(cx ls -v)
contains "$out" "~/.codex-work" "verbose view shows home paths"
contains "$out" "exp 2030-01-02" "verbose view shows expiry"
out=$(CX_COLOR=always cx ls)
contains "$out" $'\033[' "CX_COLOR=always forces colors"
ok "cx ls shows plan and subscription expiry"

# ---- 3. add / use ------------------------------------------------------------

fails cx add "bad name"
fails cx add work
SIDE="$TMP/side-home"
mkdir "$SIDE"
fails cx add dup --no-login --home "$HOME/.codex-work"   # already registered
cx add side --no-login --home "$SIDE"
out=$(cx ls)
contains "$out" "side" "add registers new account"

cx use side
[[ $CODEX_HOME == $SIDE ]] || die "cx use side did not set CODEX_HOME"
cx use -
[[ -z ${CODEX_HOME:-} ]] || die "cx use - did not clear CODEX_HOME"
ok "cx add / cx use works"

# ---- 4. bind in non-interactive shell (direct apply on bind) -----------------

PROJ="$TMP/proj/sub/deeper"
mkdir -p "$PROJ"
cd "$TMP/proj"
cx bind side
[[ $CODEX_HOME == $SIDE ]] || die "bind did not apply immediately"
print -rn -- "$RPROMPT" | grep -q "codex:side:auto" || die "auto marker missing: $RPROMPT"
ok "bind applies immediately with auto marker"

# ---- 5. chpwd auto-switch tested in a real interactive child shell ----------

cd "$HOME"
child=$(env -u CODEX_HOME ZDOTDIR="$HOME" HOME="$HOME" XDG_CONFIG_HOME="$TMP/config" \
  zsh -ic "
    source '$SCRIPT'
    whence -w _cx | grep -q function || { echo FAIL_COMPLETION; exit 1 }
    cd '$PROJ'
    [[ \$CODEX_HOME == '$SIDE' ]] || { echo FAIL_ENTER; exit 1 }
    print -rn -- \"\$RPROMPT\" | grep -q 'codex:side:auto' || { echo FAIL_MARKER; exit 1 }
    cd '$TMP/proj'
    [[ \$CODEX_HOME == '$SIDE' ]] || { echo FAIL_PREFIX; exit 1 }
    cd '$HOME'
    [[ -z \${CODEX_HOME:-} ]] || { echo FAIL_LEAVE; exit 1 }
    [[ -z \$CX_AUTO_ACTIVE ]] || { echo FAIL_LEAVE_STATE; exit 1 }
    echo CHPWD_OK
  " 2>&1)
contains "$child" "CHPWD_OK" "interactive chpwd auto-switch
$child"
ok "chpwd switches on cd in, keeps on prefix match, restores on leave"

# ---- 6. binds / unbind -------------------------------------------------------

cd "$PROJ"
out=$(cx binds)
contains "$out" "side" "binds lists account"
contains "$out" "$TMP/proj" "binds lists path"
cx unbind "$TMP/proj"
[[ -z ${CODEX_HOME:-} ]] || die "unbind did not restore CODEX_HOME"
ok "binds / unbind works"

# ---- 7. rm keeps data by default, then --purge deletes -----------------------

cd "$HOME"
echo n | cx rm side >/dev/null
[[ -d $SIDE ]] || die "rm should keep data directory without --purge"
out=$(cx ls)
not_contains "$out" "side" "rm unregisters"
cx add side --no-login --home "$SIDE"
cx rm side --purge
[[ ! -d $SIDE ]] || die "--purge did not delete data directory"
ok "rm keeps data then --purge deletes"
fails cx rm default
ok "default account is protected"

# ---- 8. one-shot invocation through a fake codex -----------------------------

mkdir "$TMP/bin"
cat > "$TMP/bin/codex" <<'SH'
#!/bin/sh
echo "FAKE_CODEX_HOME=$CODEX_HOME"
echo "ARGS=$*"
SH
chmod +x "$TMP/bin/codex"
out=$(PATH="$TMP/bin:$PATH" cx work hello-world)
contains "$out" "FAKE_CODEX_HOME=$HOME/.codex-work" "one-shot sets CODEX_HOME"
contains "$out" "ARGS=hello-world" "one-shot forwards arguments"
print -rn -- "$out" | grep -qx "FAKE_CODEX_HOME=$HOME/.codex-work" \
  || die "CODEX_HOME was not the only/expected value
$out"
ok "one-shot cx <account> invokes codex with correct CODEX_HOME and args"

# ---- 10. setup wizard (scripted answers) --------------------------------------

mkdir -p "$HOME/.codex-adopt"
print -r -- '{"tokens":{"id_token":"x.eyJlbWFpbCI6ImFkb3B0QGV4YW1wbGUuY29tIn0.s"}}' > "$HOME/.codex-adopt/auth.json"
# answers: register adopt=y, sign in default=n, add another=n, show usage=n
out=$(printf 'y\nn\nn\nn\n' | cx setup 2>&1)
contains "$out" "CodeX Switch setup" "setup banner"
contains "$(<"$XDG_CONFIG_HOME/codex-switch/accounts.tsv")" "adopt	$HOME/.codex-adopt" "setup registers discovered home"
out=$(cx setup </dev/null 2>&1) || die "setup must not fail on EOF"
ok "cx setup adopts existing homes and survives EOF"

# ---- 11. claude account through the zsh wrapper -------------------------------

mkdir -p "$TMP/cbin"
cp "$ROOT/tests/fake-claude" "$TMP/cbin/claude"
PATH="$TMP/cbin:$PATH" cx add --claude alt >/dev/null
contains "$(PATH="$TMP/cbin:$PATH" cx ls)" "claude@example.com" "claude account listed"
cx use alt >/dev/null 2>&1
[[ $CLAUDE_CONFIG_DIR == $HOME/.claude-alt ]] || die "cx use alt did not set CLAUDE_CONFIG_DIR"
print -rn -- "$RPROMPT" | grep -q "claude:alt" || die "claude marker missing: $RPROMPT"
cx use - >/dev/null
[[ -z ${CLAUDE_CONFIG_DIR:-} ]] || die "cx use - did not clear CLAUDE_CONFIG_DIR"
cx rm alt --purge >/dev/null
ok "claude accounts work through the zsh wrapper"

# ---- 9. version --------------------------------------------------------------

out=$(cx version)
contains "$out" "CodeX Switch" "version output"
ok "version command"

print ""
print -P -- "%F{green}All $n smoke checks passed.%f"
