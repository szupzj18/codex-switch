# CodeX Switch — parallel multi-account manager for the OpenAI Codex CLI (zsh)
# https://github.com/szupzj18/codex-switch
#
# Each account gets its own CODEX_HOME (auth.json, sessions, config, quotas).
# Accounts stay usable in parallel: one shell per account, no restart, no
# global "active account". Project bindings auto-switch on cd.

typeset -g CX_VERSION="0.1.0"
typeset -g CX_CONFIG_DIR="${CX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/codex-switch}"
typeset -g CX_ACCOUNT_FILE="$CX_CONFIG_DIR/accounts.tsv"
typeset -g CX_BINDING_FILE="$CX_CONFIG_DIR/bindings.tsv"
typeset -gA CX_ACCOUNT_HOMES
typeset -ga CX_ACCOUNT_NAMES

# ---------------------------------------------------------------------------
# Registry helpers
# ---------------------------------------------------------------------------

# On first run seed the built-in default account and auto-discover existing
# ~/.codex-* homes that already contain an auth.json. Discovery never moves
# or copies data; it only registers existing directories.
_cx_init() {
  [[ -f $CX_ACCOUNT_FILE ]] && return 0
  mkdir -p "$CX_CONFIG_DIR"
  {
    print -r -- "default	$HOME/.codex"
    local d name
    for d in "$HOME"/.codex-*(N); do
      [[ -r "$d/auth.json" ]] || continue
      name="${d:t}"
      name="${name#.codex-}"
      _cx_valid_name "$name" && [[ $name != default ]] && print -r -- "$name	$d"
    done
  } >! "$CX_ACCOUNT_FILE"
}

_cx_load_registry() {
  CX_ACCOUNT_HOMES=()
  CX_ACCOUNT_NAMES=()
  [[ -f $CX_ACCOUNT_FILE ]] || return 0
  local name home
  while IFS=$'\t' read -r name home; do
    [[ -z $name || $name == \#* ]] && continue
    CX_ACCOUNT_HOMES[$name]=$home
    CX_ACCOUNT_NAMES+=("$name")
  done < "$CX_ACCOUNT_FILE"
}

_cx_load_registry

_cx_reserved=(ls list status use login off reset unset help add rm bind unbind binds version -h --help)
_cx_valid_name() {
  [[ $1 =~ '^[A-Za-z0-9_-]+$' ]] || return 1
  local r
  for r in $_cx_reserved; do [[ $1 == $r ]] && return 1; done
  return 0
}

_cx_init
_cx_load_registry

# ---------------------------------------------------------------------------
# Auth introspection
# ---------------------------------------------------------------------------

# Decode the signed-in email from auth.json's id_token (JWT) locally.
# Never prints tokens. Works without python3 (skips the column).
_cx_account_email() {
  local auth="$1/auth.json"
  if [[ ! -r $auth ]]; then
    print "(not signed in)"
  elif ! (( $+commands[python3] )); then
    print "(signed in)"
  else
    python3 - "$auth" <<'PY' 2>/dev/null || print "(unknown)"
import json, sys, base64
d = json.load(open(sys.argv[1]))
t = (d.get("tokens") or {}).get("id_token")
if not t:
    print("API key" if d.get("OPENAI_API_KEY") else "(no credentials)")
    sys.exit(0)
p = t.split(".")[1]
p += "=" * (-len(p) % 4)
c = json.loads(base64.urlsafe_b64decode(p))
print(c.get("email") or c.get("preferred_username") or c.get("sub", "?"))
PY
  fi
}

_cx_current_account() {
  [[ -z $CODEX_HOME ]] && { print default; return; }
  local k
  for k in $CX_ACCOUNT_NAMES; do
    [[ $CX_ACCOUNT_HOMES[$k] == $CODEX_HOME ]] && { print $k; return; }
  done
  print custom
}

# ---------------------------------------------------------------------------
# Project bindings (auto-switch on cd; longest-prefix match)
# ---------------------------------------------------------------------------

_cx_binding_for() {
  local dir="$1" name path best_path="" best_name=""
  [[ -f $CX_BINDING_FILE ]] || return 0
  while IFS=$'\t' read -r name path; do
    [[ -z $name || $name == \#* ]] && continue
    if [[ $dir == $path || $dir == $path/* ]]; then
      if (( $#best_path == 0 || ${#path} > ${#best_path} )); then
        best_path=$path best_name=$name
      fi
    fi
  done < "$CX_BINDING_FILE"
  [[ -n $best_name ]] && print -r -- "$best_name"
  return 0
}

_cx_apply_binding() {
  local bound target
  bound=$(_cx_binding_for "$PWD")
  if [[ -n $bound ]]; then
    target=$CX_ACCOUNT_HOMES[$bound]
    [[ -z $target ]] && return 0
    if [[ $CX_AUTO_ACTIVE != $bound ]]; then
      [[ -z $CX_AUTO_ACTIVE ]] && _CX_PRE_AUTO_HOME=${CODEX_HOME:-}
      export CODEX_HOME=$target
      CX_AUTO_ACTIVE=$bound
    fi
  elif [[ -n $CX_AUTO_ACTIVE ]]; then
    if [[ -n $_CX_PRE_AUTO_HOME ]]; then
      export CODEX_HOME=$_CX_PRE_AUTO_HOME
    else
      unset CODEX_HOME
    fi
    CX_AUTO_ACTIVE=
    _CX_PRE_AUTO_HOME=
  fi
  _cx_rprompt
}

# ---------------------------------------------------------------------------
# cx
# ---------------------------------------------------------------------------

cx() {
  local sub="${1:-ls}"
  case $sub in
    ls|list|status)
      local cur k email mark
      cur=$(_cx_current_account)
      print " codex accounts (* active in this shell, a auto-switch by directory)"
      for k in $CX_ACCOUNT_NAMES; do
        email=$(_cx_account_email "$CX_ACCOUNT_HOMES[$k]")
        mark=" "
        [[ $k == $cur ]] && mark="*"
        [[ $CX_AUTO_ACTIVE == $k ]] && mark="a"
        printf ' %s %-12s %-18s %s\n' "$mark" "$k" "${CX_ACCOUNT_HOMES[$k]/#$HOME/~}" "$email"
      done
      ;;

    use)
      local name="${2:-}"
      if [[ -z $name || $name == - ]]; then
        unset CODEX_HOME
        _cx_rprompt
        print "codex account: default ($HOME/.codex)"
      elif (( $+CX_ACCOUNT_HOMES[$name] )); then
        [[ -d $CX_ACCOUNT_HOMES[$name] ]] || { print "cx: directory not found: $CX_ACCOUNT_HOMES[$name]" >&2; return 1; }
        if [[ $name == default ]]; then unset CODEX_HOME; else export CODEX_HOME="$CX_ACCOUNT_HOMES[$name]"; fi
        _cx_rprompt
        print "this shell -> codex account: $name"
      else
        print "cx: unknown account '$name' (accounts: $CX_ACCOUNT_NAMES)" >&2
        return 1
      fi
      ;;

    login)
      local name="${2:-}"
      if ! (( $+CX_ACCOUNT_HOMES[$name] )); then
        print "cx: usage: cx login <${(j:/:)CX_ACCOUNT_NAMES}>" >&2; return 1
      fi
      CODEX_HOME="$CX_ACCOUNT_HOMES[$name]" codex login
      ;;

    add)
      shift
      local name="" home_override="" do_login=1 device=""
      while (( $# )); do
        case $1 in
          --home) home_override=$2; shift 2 ;;
          --no-login) do_login=0; shift ;;
          --device-auth) device="--device-auth"; shift ;;
          -*) print "cx add: unknown flag $1" >&2; return 1 ;;
          *)  if [[ -z $name ]]; then name=$1; shift
              else print "cx add: unexpected argument $1" >&2; return 1; fi ;;
        esac
      done
      if [[ -z $name ]]; then print "usage: cx add <name> [--home DIR] [--no-login] [--device-auth]" >&2; return 1; fi
      if ! _cx_valid_name "$name"; then
        print "cx: name must match [A-Za-z0-9_-] and not collide with a command: $name" >&2; return 1
      fi
      if (( $+CX_ACCOUNT_HOMES[$name] )); then
        print "cx: account '$name' already exists: $CX_ACCOUNT_HOMES[$name]" >&2; return 1
      fi
      local home="${home_override:-$HOME/.codex-$name}"
      local k
      for k in $CX_ACCOUNT_NAMES; do
        if [[ $CX_ACCOUNT_HOMES[$k] == $home ]]; then
          print "cx: directory already registered as account '$k': $home" >&2; return 1
        fi
      done
      mkdir -p "$home" || return 1
      if (( do_login )) && [[ ! -r $home/auth.json ]]; then
        print "Complete the sign-in in your browser (account: $name)..."
        CODEX_HOME="$home" codex login $device || {
          print "cx: login failed; account not registered (directory kept: $home)" >&2; return 1
        }
      fi
      print -r -- "$name	$home" >> "$CX_ACCOUNT_FILE"
      _cx_load_registry
      print "added account: $name -> $home"
      (( do_login )) || print "not signed in yet: run  cx login $name"
      ;;

    rm)
      local name="${2:-}" purge=0 ans
      [[ $3 == --purge ]] && purge=1
      if [[ -z $name ]]; then print "usage: cx rm <name> [--purge]" >&2; return 1; fi
      if [[ $name == default ]]; then print "cx: default is built-in and cannot be removed" >&2; return 1; fi
      if ! (( $+CX_ACCOUNT_HOMES[$name] )); then
        print "cx: unknown account '$name' (accounts: $CX_ACCOUNT_NAMES)" >&2; return 1
      fi
      if [[ $CX_ACCOUNT_HOMES[$name] == ${CODEX_HOME:-} ]]; then
        print "cx: '$name' is active in this shell; run 'cx use -' first" >&2; return 1
      fi
      local home="$CX_ACCOUNT_HOMES[$name]" tmp n p
      tmp="${CX_ACCOUNT_FILE}.tmp"
      while IFS=$'\t' read -r n p; do
        [[ -z $n ]] && continue
        [[ $n == \#* ]] && { print -r -- "$n	$p"; continue }
        [[ $n == $name ]] || print -r -- "$n	$p"
      done < "$CX_ACCOUNT_FILE" >! "$tmp" && mv "$tmp" "$CX_ACCOUNT_FILE"
      if [[ -f $CX_BINDING_FILE ]]; then
        tmp="${CX_BINDING_FILE}.tmp"
        while IFS=$'\t' read -r n p; do
          [[ -z $n ]] && continue
          [[ $n == \#* ]] && { print -r -- "$n	$p"; continue }
          [[ $n == $name ]] || print -r -- "$n	$p"
        done < "$CX_BINDING_FILE" >! "$tmp" && mv "$tmp" "$CX_BINDING_FILE"
      fi
      _cx_load_registry
      print "removed account from registry: $name"
      if (( purge == 0 )) && [[ -d $home ]] && [[ -o interactive ]]; then
        read -q "ans?Also delete data directory $home ? This cannot be undone [y/N] " || true
        print
        [[ $ans == y ]] && purge=1
      fi
      if (( purge )); then
        rm -rf "$home" && print "deleted data directory: $home"
      elif [[ -d $home ]]; then
        print "data directory kept: $home (delete it yourself, or re-register with cx add)"
      fi
      ;;

    bind)
      local name="${2:-}" dir="$PWD"
      if [[ -z $name ]]; then
        if [[ -z $CODEX_HOME ]]; then
          print "cx: currently on default; use 'cx bind <name>' or 'cx use <name>' first" >&2; return 1
        fi
        name=$(_cx_current_account)
      fi
      if ! (( $+CX_ACCOUNT_HOMES[$name] )); then
        print "cx: unknown account '$name' (accounts: $CX_ACCOUNT_NAMES)" >&2; return 1
      fi
      local n p tmp="${CX_BINDING_FILE}.tmp" existed=0
      {
        [[ -f $CX_BINDING_FILE ]] && while IFS=$'\t' read -r n p; do
          if [[ -z $n ]]; then continue
          elif [[ $n == \#* ]]; then print -r -- "$n	$p"
          elif [[ $p == $dir ]]; then existed=1; print -r -- "$name	$dir"
          else print -r -- "$n	$p"; fi
        done < "$CX_BINDING_FILE"
        (( existed )) || print -r -- "$name	$dir"
      } >! "$tmp" && mv "$tmp" "$CX_BINDING_FILE"
      print "bound: $dir -> $name (auto-switch in this directory and subdirectories)"
      (( existed )) && print "(replaced previous binding for this directory)"
      _cx_apply_binding
      ;;

    unbind)
      local dir="${2:-$PWD}"
      [[ -f $CX_BINDING_FILE ]] || { print "cx: no project bindings"; return; }
      local tmp="${CX_BINDING_FILE}.tmp" n p removed=0
      while IFS=$'\t' read -r n p; do
        if [[ -z $n ]]; then continue
        elif [[ $n == \#* ]]; then print -r -- "$n	$p"
        elif [[ $p == $dir ]]; then removed=1
        else print -r -- "$n	$p"; fi
      done < "$CX_BINDING_FILE" >! "$tmp" && mv "$tmp" "$CX_BINDING_FILE"
      if (( removed )); then print "unbound: $dir"; _cx_apply_binding
      else print "cx: no binding for $dir"; fi
      ;;

    binds)
      if [[ ! -s $CX_BINDING_FILE ]]; then
        print "(no project bindings yet — run 'cx bind <name>' inside a project directory)"
        return
      fi
      local cur n p mark
      cur=$(_cx_binding_for "$PWD")
      print " account       project directory (* active here)"
      while IFS=$'\t' read -r n p; do
        [[ -z $n || $n == \#* ]] && continue
        mark="  "
        [[ $n == $cur && ( $PWD == $p || $PWD == $p/* ) ]] && mark="* "
        printf ' %s%-12s %s\n' "$mark" "$n" "$p"
      done < "$CX_BINDING_FILE"
      ;;

    version|-v|--version)
      print "CodeX Switch $CX_VERSION"
      ;;

    off|reset|unset)
      unset CODEX_HOME
      _cx_rprompt
      print "cleared CODEX_HOME; back to default account"
      ;;

    help|-h|--help)
      print -P -- "%Bcx%b — CodeX Switch: parallel multi-account manager for Codex CLI"
      cat <<EOF
  cx                         list accounts and signed-in emails
  cx use <name>              switch this shell to <name> (RPROMPT marker)
  cx use -                   switch this shell back to default
  cx <name> [codex args]     one-shot invocation, e.g.  cx work exec "..."
  cx login <name>            run codex login for one account
  cx off                     clear the switch
  cx add <name>              create an account (new CODEX_HOME + sign-in)
      [--home DIR] [--no-login] [--device-auth]
  cx rm <name> [--purge]     unregister (keeps data unless confirmed/--purge)
  cx bind [name]             bind current directory (default: current account)
  cx unbind [dir]            remove a directory binding (default: current dir)
  cx binds                   list project bindings
  cx version                 print CodeX Switch version

  accounts: $CX_ACCOUNT_NAMES
  files:    $CX_ACCOUNT_FILE
            $CX_BINDING_FILE
EOF
      ;;

    *)
      if (( $+CX_ACCOUNT_HOMES[$sub] )); then
        CODEX_HOME="$CX_ACCOUNT_HOMES[$sub]" codex "${@[2,-1]}"
      else
        print "cx: unknown command/account '$sub' (cx help)" >&2
        return 1
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Prompt marker + cd hook
# ---------------------------------------------------------------------------

_cx_rprompt() {
  [[ -z $CODEX_HOME ]] && { RPROMPT=""; return; }
  local cur
  cur=$(_cx_current_account)
  if [[ $cur == custom ]]; then
    RPROMPT="%F{cyan}[codex:custom]%f"
  elif [[ -n $CX_AUTO_ACTIVE && $CX_ACCOUNT_HOMES[$CX_AUTO_ACTIVE] == $CODEX_HOME ]]; then
    RPROMPT="%F{yellow}[codex:${cur}:auto]%f"
  else
    RPROMPT="%F{cyan}[codex:${cur}]%f"
  fi
}

typeset -g CX_AUTO_ACTIVE="" _CX_PRE_AUTO_HOME=""
if [[ -o interactive ]]; then
  if [[ -z ${precmd_functions[(r)_cx_rprompt]} ]]; then
    precmd_functions+=(_cx_rprompt)
  fi
  if [[ -z ${chpwd_functions[(r)_cx_apply_binding]} ]]; then
    chpwd_functions=(_cx_apply_binding $chpwd_functions)
  fi
  _cx_apply_binding
fi

_cx() {
  if (( CURRENT == 2 )); then
    _alternative \
      'subcommands:cx command:(ls use login off add rm bind unbind binds version help)' \
      "accounts:codex account:($CX_ACCOUNT_NAMES)"
  elif (( CURRENT == 3 )); then
    case $words[2] in
      use|login|bind) _wanted accounts expl 'codex account' compadd -- $CX_ACCOUNT_NAMES ;;
      rm) _wanted accounts expl 'codex account' compadd -- ${CX_ACCOUNT_NAMES:#default} ;;
    esac
  fi
}
(( $+functions[compdef] )) && compdef _cx cx
return 0
