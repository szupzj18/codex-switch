#!/usr/bin/env zsh
# Zorua install-time end-to-end test.
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
inst=$(su "$E2E_USER" -s "$ZSH_BIN" -c "sh $SRC/install.sh")
print -r -- "$inst" | grep -q "added source block"
[[ -f $UH/.zshrc ]] || die ".zshrc not created"
grep -q '# >>> zorua >>>' "$UH/.zshrc" || die "marker begin missing"
grep -q '# <<< zorua <<<' "$UH/.zshrc" || die "marker end missing"
for f in cx_core.py cx_statusline.py zorua.zsh zorua.bash zorua.fish; do
  [[ -f $UH/.zorua/$f ]] || die "$f not installed"
done
grep -q '# >>> zorua >>>' "$UH/.bashrc" || die "bashrc block missing"
if (( $+commands[fish] )); then
  grep -q 'zorua.fish' "$UH/.config/fish/conf.d/zorua.fish" || die "fish conf.d missing"
fi
ok "install.sh (plain sh) worked for $E2E_USER: core + zsh/bash/fish wired"

step "2. installer is idempotent"
inst=$(su "$E2E_USER" -s "$ZSH_BIN" -c "sh $SRC/install.sh")
print -r -- "$inst" | grep -q "already present"
(( $(grep -c 'zorua >>>' $UH/.zshrc) == 1 )) || die "marker block duplicated"
ok "second install does not duplicate the block"

step "3. fresh interactive zsh works + add/use + fake codex + bind/unbind"

cat > "$UH/scenario.zsh" <<EOF
emulate -L zsh
set -e

export PATH="\$HOME/bin:\$PATH"

cx version | grep -q "Zorua"
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

step "3b. bash and fish wrappers work in a fresh interactive shell"
cat > "$UH/scenario.bash" <<'EOF'
set -e
export PATH="$HOME/bin:$PATH"
cx version | grep -q "Zorua"
cx add demo2 --no-login >/dev/null
cx use demo2 >/dev/null
[ "$CODEX_HOME" = "$HOME/.codex-demo2" ]
[ "$CX_PROMPT_TEXT" = "[codex:demo2]" ]
cx use - >/dev/null
[ -z "${CODEX_HOME:-}" ]
mkdir -p "$HOME/bw"
cd "$HOME/bw"
cx bind demo2 >/dev/null
cd "$HOME"; _cx_prompt_hook; cd "$HOME/bw"; _cx_prompt_hook
[ "$CODEX_HOME" = "$HOME/.codex-demo2" ]
cd "$HOME"; _cx_prompt_hook
[ -z "${CODEX_HOME:-}" ]
cx rm demo2 --purge >/dev/null
echo E2E_BASH_OK
EOF
chown "$E2E_USER" "$UH/scenario.bash"
out=$(su "$E2E_USER" -s /bin/bash -c "bash -i -c 'source \$HOME/.zorua/zorua.bash; source \$HOME/scenario.bash'" 2>&1) || { print "$out" >&2; die "bash scenario failed"; }
print "$out" | grep -q E2E_BASH_OK || die "bash scenario did not report success
$out"
ok "bash wrapper: add/use/prompt/bind/hook/rm"
if (( $+commands[fish] )); then
  cat > "$UH/scenario.fish" <<'EOF'
cx version | grep -q "Zorua"; or exit 1
cx add demo3 --no-login >/dev/null; or exit 1
cx use demo3 >/dev/null
test "$CODEX_HOME" = "$HOME/.codex-demo3"; or begin; echo BAD_USE; exit 1; end
cx use - >/dev/null
test -z "$CODEX_HOME"; or begin; echo BAD_CLEAR; exit 1; end
mkdir -p $HOME/fw
cd $HOME/fw
cx bind demo3 >/dev/null
cd $HOME
cd $HOME/fw
test "$CODEX_HOME" = "$HOME/.codex-demo3"; or begin; echo BAD_BIND; exit 1; end
cd $HOME
test -z "$CODEX_HOME"; or begin; echo BAD_LEAVE; exit 1; end
cx rm demo3 --purge >/dev/null
echo E2E_FISH_OK
EOF
  chown "$E2E_USER" "$UH/scenario.fish"
  out=$(su "$E2E_USER" -s "$(whence -p fish)" -c "source \$HOME/.zorua/zorua.fish; source \$HOME/scenario.fish" 2>&1) || { print "$out" >&2; die "fish scenario failed"; }
  print "$out" | grep -q E2E_FISH_OK || die "fish scenario did not report success
$out"
  ok "fish wrapper: add/use/bind/hook/rm"
fi

step "4. without python3 every wrapper explains what is missing"
cat > "$UH/no-py.zsh" <<'EOF'
cx ls
EOF
chown "$E2E_USER" "$UH/no-py.zsh"
out=$(su "$E2E_USER" -s "$ZSH_BIN" -c "PATH=/nonexistent $ZSH_BIN -i \$HOME/no-py.zsh" 2>&1) || true
print "$out" | grep -q "python3 is required" || die "no-python message missing
$out"
ok "clear message when python3 is missing"

step "4b. upgrading from the old codex-switch install"
OLD_USER="${E2E_USER}old"
id "$OLD_USER" >/dev/null 2>&1 && userdel -r "$OLD_USER"
useradd -m -s "$ZSH_BIN" "$OLD_USER"
OH=$(getent passwd "$OLD_USER" | cut -d: -f6)
mkdir -p "$OH/.codex-switch" "$OH/.config/codex-switch" "$OH/.codex-keep"
echo "stale old script" > "$OH/.codex-switch/codex-switch.zsh"
printf 'default\t%s/.codex\nkeep\t%s/.codex-keep\n' "$OH" "$OH" > "$OH/.config/codex-switch/accounts.tsv"
printf 'export FOO=1\n\n# >>> codex-switch >>>\nsource "%s/.codex-switch/codex-switch.zsh"\n# <<< codex-switch <<<\n' "$OH" > "$OH/.zshrc"
chown -R "$OLD_USER" "$OH"
inst=$(su "$OLD_USER" -s "$ZSH_BIN" -c "sh $SRC/install.sh")
print -r -- "$inst" | grep -q "migrated: removed the old codex-switch block" || die "legacy block not migrated
$inst"
! grep -q 'codex-switch' "$OH/.zshrc" || die "legacy source line still in .zshrc"
grep -q 'FOO=1' "$OH/.zshrc" || die "unrelated .zshrc content must survive"
(( $(grep -c '# >>> zorua >>>' "$OH/.zshrc") == 1 )) || die "new block missing or duplicated"
out=$(su "$OLD_USER" -s "$ZSH_BIN" -c "$ZSH_BIN -i -c 'cx ls'" 2>&1)
print -r -- "$out" | grep -q "keep" || die "accounts were not carried over
$out"
[[ -d $OH/.config/codex-switch ]] || die "old config must be kept as a backup"
userdel -r "$OLD_USER" 2>/dev/null || true
ok "old install migrated: rc block replaced, accounts carried over, backup kept"

step "5. uninstaller removes the block but never account data"
mkdir -p "$UH/.codex-demo"
un=$(su "$E2E_USER" -s "$ZSH_BIN" -c "sh $SRC/uninstall.sh")
print -r -- "$un" | grep -q "removed source block"
! grep -q zorua "$UH/.zshrc" || die "zshrc still references zorua"
! grep -q zorua "$UH/.bashrc" || die "bashrc still references zorua"
[[ ! -e $UH/.config/fish/conf.d/zorua.fish ]] || die "fish conf.d not removed"
[[ -d $UH/.codex-demo && -f $UH/.config/zorua/accounts.tsv ]] || die "account data was deleted"
ok "uninstall.sh clean, data intact"

step "6. syntax"
zsh -n "$SRC/zorua.zsh"
bash -n "$SRC/zorua.bash"
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$SRC/cx_core.py"
sh -n "$SRC/install.sh"
sh -n "$SRC/uninstall.sh"
if (( $+commands[fish] )); then fish -n "$SRC/zorua.fish"; fi
ok "all scripts parse"

print ""
print -P -- "%F{green}All $n install E2E checks passed.%f"
