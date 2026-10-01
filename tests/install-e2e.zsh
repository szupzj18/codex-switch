#!/usr/bin/env zsh
# CodeX Switch install-time end-to-end test.
#
# Runs as ROOT inside a bare Linux container (ubuntu:24.04 + zsh), creates a
# fresh unprivileged user, and exercises the full user journey that unit-ish
# smoke.zsh does not cover:
#
#   install.sh -> fresh interactive zsh loads it -> add/use/bind with a fake
#   codex on PATH -> idempotent reinstall -> no-python3 fallback -> uninstall
#
# Local (OrbStack/Docker):
#   docker run --rm -v "$PWD":/src:ro -w /src ubuntu:24.04 \
#     bash -c "apt-get update -qq && apt-get install -y -qq zsh python3 && zsh tests/install-e2e.zsh"
#
# CI runs the same script inside the workflow's ubuntu:24.04 container job.

emulate -L zsh
set -e
setopt pipe_fail

SRC="${CX_E2E_SRC:-/src}"
E2E_USER="${CX_E2E_USER:-cxuser}"
ZSH_BIN="${CX_E2E_ZSH:-$(whence -p zsh)}"

(( EUID == 0 )) || { print "this script must run as root (it creates a fresh user)" >&2; exit 2; }
[[ -n $ZSH_BIN && -x $ZSH_BIN ]] || { print "zsh not found" >&2; exit 2; }
[[ -f $SRC/install.sh ]] || { print "source tree not found at $SRC (set CX_E2E_SRC)" >&2; exit 2; }

n=0
ok() { n=$((n + 1)); print -P -- "%F{green}ok%f $1"; }
step() { print ""; print -P -- "%B==> %f$1"; }
die() { print -P -- "%F{red}FAIL%f $1" >&2; exit 1; }

# Fresh user (idempotent reruns)
id "$E2E_USER" >/dev/null 2>&1 && userdel -r "$E2E_USER"
useradd -m -s "$ZSH_BIN" "$E2E_USER"
UH=$(getent passwd "$E2E_USER" | cut -d: -f6)

step "1. installer writes zshrc block as a non-root user"
inst=$(su "$E2E_USER" -s "$ZSH_BIN" -c "zsh $SRC/install.sh")
print -r -- "$inst" | grep -q "added source block"
[[ -f $UH/.zshrc ]] || die ".zshrc not created"
grep -q '# >>> codex-switch >>>' "$UH/.zshrc" || die "marker begin missing"
grep -q '# <<< codex-switch <<<' "$UH/.zshrc" || die "marker end missing"
ok "install.sh worked for $E2E_USER"

step "2. installer is idempotent"
inst=$(su "$E2E_USER" -s "$ZSH_BIN" -c "zsh $SRC/install.sh")
print -r -- "$inst" | grep -q "already present"
(( $(grep -c 'codex-switch >>>' $UH/.zshrc) == 1 )) || die "marker block duplicated"
ok "second install does not duplicate the block"

step "3. fresh interactive zsh works + add/use + fake codex + bind/unbind"

cat > "$UH/scenario.zsh" <<EOF
emulate -L zsh
set -e

export PATH="\$HOME/bin:\$PATH"

cx version | grep -q "CodeX Switch"
out=\$(cx ls)
print -rn -- "\$out" | grep -q default
if print -rn -- "\$out" | grep -q demo; then echo FAIL_DEMO_PRESENT; exit 1; fi

cx add demo --no-login
if cx add demo 2>/dev/null; then echo FAIL_DUP_NAME; exit 1; fi
cx ls | grep -q demo

# Fake codex: one-shot invocation must set CODEX_HOME and forward args
mkdir -p \$HOME/bin
cat > \$HOME/bin/codex <<'SH'
#!/bin/sh
echo "FAKE_HOME=\$CODEX_HOME"
echo "ARGS=\$*"
SH
chmod +x \$HOME/bin/codex
out=\$(cx demo exec "hello-e2e")
print -rn -- "\$out" | grep -q "FAKE_HOME=\$HOME/.codex-demo"
print -rn -- "\$out" | grep -q "ARGS=exec hello-e2e"

# cx use affects only this shell + prompt marker
cx use demo
[[ \$CODEX_HOME == \$HOME/.codex-demo ]]
print -rn -- "\$RPROMPT" | grep -q "codex:demo"
cx use -
[[ -z \${CODEX_HOME:-} ]]

# bind immediately applies; chpwd keeps on prefix match; leave restores
mkdir -p \$HOME/work/api/sub
cd \$HOME/work/api
cx bind demo
[[ \$CODEX_HOME == \$HOME/.codex-demo ]]
cd sub
[[ \$CODEX_HOME == \$HOME/.codex-demo && \$CX_AUTO_ACTIVE == demo ]]
cd \$HOME
[[ -z \${CODEX_HOME:-} && -z \$CX_AUTO_ACTIVE ]]

cx binds | grep -q "/work/api"
cx unbind \$HOME/work/api
[[ -z \${CODEX_HOME:-} ]]

cx rm demo --purge
! cx ls | grep -q demo
echo E2E_SCENARIO_OK
EOF
chown "$E2E_USER" "$UH/scenario.zsh"

scenario_out=$(su "$E2E_USER" -s "$ZSH_BIN" -c "$ZSH_BIN -i \$HOME/scenario.zsh" 2>&1) || {
  print "$scenario_out" >&2
  die "interactive-shell scenario failed"
}
print "$scenario_out" | grep -q E2E_SCENARIO_OK || die "scenario did not report success"
ok "all interactive commands work in a fresh user shell"

step "4. cx ls without python3 degrades gracefully"
mkdir -p "$UH/.codex-demo" "$UH/.config/codex-switch"
printf 'garbage-non-json\n' > "$UH/.codex-demo/auth.json"
printf 'default\t%s\ndemo\t%s\n' "$UH/.codex" "$UH/.codex-demo" > "$UH/.config/codex-switch/accounts.tsv"
chown -R "$E2E_USER" "$UH/.config" "$UH/.codex-demo"
cat > "$UH/no-py.zsh" <<'EOF'
export PATH=/nonexistent
cx ls
EOF
chown "$E2E_USER" "$UH/no-py.zsh"
out=$(su "$E2E_USER" -s "$ZSH_BIN" -c "$ZSH_BIN -i \$HOME/no-py.zsh" 2>&1)
print "$out" | grep -q "signed in" || die "no-python fallback message missing
$out"
if print -rn -- "$out" | grep -q "command not found"; then die "spurious error with no python3
$out"; fi
ok "email column falls back without python3"

step "5. uninstaller removes the block but never account data"
un=$(su "$E2E_USER" -s "$ZSH_BIN" -c "zsh $SRC/uninstall.sh")
print -r -- "$un" | grep -q "removed source block"
! grep -q codex-switch "$UH/.zshrc" || die "zshrc still references codex-switch"
[[ -d $UH/.codex-demo && -f $UH/.config/codex-switch/accounts.tsv ]] || die "account data was deleted"
ok "uninstall.sh clean, data intact"

step "6. script syntax"
zsh -n "$SRC/codex-switch.zsh"
ok "codex-switch.zsh parses"

print ""
print -P -- "%F{green}All $n install E2E checks passed.%f"
