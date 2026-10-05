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

_cx_reserved=(ls list status usage setup use login off reset unset help add rm bind unbind binds version -h --help)
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

# Render the account table. $1: 1 = fetch live limits, $2: 1 = verbose blocks.
# Colors only on a TTY (or CX_COLOR=always); NO_COLOR disables them.
_cx_render() {
  local online=$1 verbose=$2 color=0 k
  [[ ( -t 1 && -z $NO_COLOR ) || $CX_COLOR == always ]] && color=1
  local -a args
  for k in $CX_ACCOUNT_NAMES; do args+=("$k=$CX_ACCOUNT_HOMES[$k]"); done
  PYTHONIOENCODING=utf-8 python3 - $online $verbose $color "$(_cx_current_account)" "$CX_AUTO_ACTIVE" $args <<'PY'
import json, sys, os, math, base64, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

online, verbose, color = (sys.argv[i] == "1" for i in (1, 2, 3))
cur, auto = sys.argv[4], sys.argv[5]
accts = [a.split("=", 1) for a in sys.argv[6:]]
HOME = os.environ.get("HOME", "")

def paint(code, s):
    return "\033[%sm%s\033[0m" % (code, s) if color and code else s

def load(home):
    r = {"email": None, "plan": None, "until": None, "tok": {}, "state": "ok"}
    try:
        d = json.load(open(home + "/auth.json"))
    except Exception:
        r["state"] = "none"; return r
    t = d.get("tokens") or {}
    r["tok"] = t
    if not t.get("id_token"):
        r["state"] = "apikey" if d.get("OPENAI_API_KEY") else "none"; return r
    try:
        p = t["id_token"].split(".")[1]
        p += "=" * (-len(p) % 4)
        c = json.loads(base64.urlsafe_b64decode(p))
    except Exception:
        r["state"] = "bad"; return r
    a = c.get("https://api.openai.com/auth") or {}
    r["email"] = c.get("email") or c.get("preferred_username") or c.get("sub")
    r["plan"] = a.get("chatgpt_plan_type")
    r["until"] = (a.get("chatgpt_subscription_active_until") or "")[:10] or None
    return r

def fetch(tok):
    if not tok.get("access_token"):
        return None, "-"
    req = urllib.request.Request(
        "https://chatgpt.com/backend-api/wham/usage",
        headers={"Authorization": "Bearer " + tok["access_token"],
                 "chatgpt-account-id": tok.get("account_id", ""),
                 "User-Agent": "codex-switch"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=15)), None
    except urllib.error.HTTPError as e:
        return None, ("token expired (run codex once to refresh)" if e.code in (401, 403) else "HTTP %d" % e.code)
    except Exception as e:
        r = getattr(e, "reason", e)
        return None, "network error: %s (check proxy)" % (str(r) or type(r).__name__)

info = {n: load(h) for n, h in accts}
live = {}
if online:
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {n: ex.submit(fetch, info[n]["tok"]) for n, _ in accts if info[n]["state"] == "ok"}
        live = {n: f.result() for n, f in futs.items()}

def left(s):
    s = int(s)
    d, h, m = s // 86400, s % 86400 // 3600, s % 3600 // 60
    return "%dd%dh" % (d, h) if d and h else "%dd" % d if d else "%dh%dm" % (h, m) if h else "%dm" % m

def label(s):
    s = int(s)
    return "%dH" % (s // 3600) if s < 86400 else "%dD" % (s // 86400)

def pct_code(p):
    return "31" if p >= 80 else "33" if p >= 50 else "32"

def bar(p, n):
    f = math.ceil(p / 100 * n) if p > 0 else 0
    return paint(pct_code(p), "▓" * f) + paint("2", "░" * (n - f))

PLAN = {"pro": "36", "promax": "35", "team": "34", "plus": "32"}
today = date.today()
stale = False

def expiry(u):
    global stale
    if not u:
        return "–", "2"
    try:
        days = (date.fromisoformat(u) - today).days
    except ValueError:
        return u, None
    if days <= 7:
        stale = True
        return u + " ⚠", "31"
    return u, None

def windows(n):
    """-> (data, err, [(label, used%, reset_seconds)])"""
    d, err = live.get(n, (None, None))
    ws = []
    if d:
        rl = d.get("rate_limit") or {}
        for k in ("primary_window", "secondary_window"):
            w = rl.get(k)
            if w:
                ws.append((label(w["limit_window_seconds"]), w["used_percent"], w["reset_after_seconds"], w["limit_window_seconds"]))
    return d, err, ws

def short(h):
    return "~" + h[len(HOME):] if HOME and h.startswith(HOME) else h

def who(n):
    i = info[n]
    return i["email"] or {"none": "(not signed in)", "apikey": "API key", "bad": "(unknown)"}.get(i["state"], "?")

def mark(n):
    return paint("36", "●") if n == cur else paint("33", "◆") if n == auto else " "

def table(rows, header):
    """rows: list of list of (plain, code). Left-aligned columns, ANSI-safe."""
    widths = [max(len(r[i][0]) for r in [header] + rows) for i in range(len(header))]
    for r in [header] + rows:
        out = []
        for i, (s, code) in enumerate(r):
            pad = " " * (widths[i] - len(s))
            out.append(paint(code, s) + pad if i < len(r) - 1 else paint(code, s))
        print(" " + "  ".join(out).rstrip())

def head(*cols):
    return [(c, "2") for c in cols]

print()
if verbose:
    sep = paint("2", " " + "─" * 58)
    for n, h in accts:
        i = info[n]
        d, err, ws = windows(n)
        plan = (d or {}).get("plan_type") or i["plan"]
        exp, ecode = expiry(i["until"])
        print(sep)
        print(" %s %s  %s  %s  %s" % (mark(n), paint("1", "%-10s" % n), who(n),
              paint(PLAN.get(plan, "2"), plan or "–"), paint(ecode, "exp " + exp) if i["until"] else ""))
        print("   " + paint("2", short(h)))
        if err:
            print("   " + paint("31", err))
        for lab, p, rs, _ in ws:
            print("   %-3s %s %3d%%   %s" % (lab.lower(), bar(p, 20), p, paint("2", "resets in " + left(rs))))
        c = (d or {}).get("credits") or {}
        if c.get("has_credits") and c.get("balance"):
            print("   " + paint("2", "credits %s" % format(int(float(c["balance"])), ",")))
    print(sep)
elif online:
    rows = []
    for n, h in accts:
        i = info[n]
        d, err, ws = windows(n)
        plan = (d or {}).get("plan_type") or i["plan"]
        exp, ecode = expiry(i["until"])
        row = [(" " if False else "", None)]
        row = [(("● " if n == cur else "◆ " if n == auto else "  ") + n, None), (plan or "–", PLAN.get(plan, "2"))]
        if err or i["state"] != "ok":
            row.append((err or who(n), "31"))
            rows.append(row); continue
        w5 = next((w for w in ws if w[3] < 86400), None)
        w7 = next((w for w in ws if w[3] >= 86400), None)
        for w in (w5, w7):
            if w:
                row.append(("%s %3d%%" % ("▓" * math.ceil(w[1] / 100 * 6) + "░" * (6 - math.ceil(w[1] / 100 * 6)) if w[1] > 0 else "░" * 6, w[1]), pct_code(w[1])))
            else:
                row.append(("–", "2"))
        row.append((left(w7[2]) if w7 else left(w5[2]) if w5 else "–", None))
        row.append((exp, ecode))
        rows.append(row)
    table(rows, head("  NAME", "PLAN", "5H", "7D", "RESET", "EXPIRES"))
else:
    rows = []
    for n, h in accts:
        i = info[n]
        exp, ecode = expiry(i["until"])
        rows.append([(("● " if n == cur else "◆ " if n == auto else "  ") + n, None),
                     (who(n), None), (i["plan"] or "–", PLAN.get(i["plan"], "2")), (exp, ecode)])
    table(rows, head("  NAME", "ACCOUNT", "PLAN", "EXPIRES"))

print()
notes = []
if any(n == cur for n, _ in accts) or auto:
    notes.append("● this shell  ◆ auto-bound directory")
if stale:
    notes.append("⚠ expired or within 7 days (date comes from the cached sign-in token, may be stale)")
if not online:
    notes.append("cx usage: live limits  ·  cx ls -v: details")
for t in notes:
    print(" " + paint("2", t))
print()
PY
}

# Interactive yes/no. $1 prompt, $2 default (y|n). EOF on stdin = take the default.
_cx_confirm() {
  local ans def="${2:-y}" hint="[Y/n]"
  [[ $def == n ]] && hint="[y/N]"
  read -r "ans?$1 $hint " || { ans=""; print; }
  [[ -z $ans ]] && ans=$def
  [[ $ans == [Yy]* ]]
}

# Interactive first-run wizard: check codex, adopt existing ~/.codex-* homes,
# sign in accounts that need it, optionally add more and bind this directory.
_cx_setup() {
  local k d name home ans
  print -P "%B CodeX Switch setup%b"
  print

  if (( $+commands[codex] )); then
    print " ✓ codex found: $(command -v codex)"
  else
    print " ! codex not found on PATH — install the Codex CLI first (accounts can still be registered)"
  fi
  if (( $+commands[python3] )); then
    print " ✓ python3 found (email/plan/usage columns enabled)"
  else
    print " - python3 not found: email/plan/usage columns will be skipped"
  fi
  print

  # 1. adopt unregistered ~/.codex-* homes that already hold a sign-in
  local -a found
  for d in "$HOME"/.codex-*(N/); do
    [[ -r $d/auth.json ]] || continue
    for k in $CX_ACCOUNT_NAMES; do [[ $CX_ACCOUNT_HOMES[$k] == $d ]] && continue 2; done
    found+=("$d")
  done
  for d in $found; do
    name="${d:t}"; name="${name#.codex-}"
    if ! _cx_valid_name "$name" || (( $+CX_ACCOUNT_HOMES[$name] )); then
      print " - skipping ${d/#$HOME/~}: '$name' is not a usable account name (register it with: cx add <name> --home ${d/#$HOME/~} --no-login)"
      continue
    fi
    if _cx_confirm " Found signed-in home ${d/#$HOME/~} ($(_cx_account_email "$d")). Register as '$name'?" y; then
      print -r -- "$name	$d" >> "$CX_ACCOUNT_FILE"
      _cx_load_registry
    fi
  done

  # 2. registered accounts without a sign-in
  for k in $CX_ACCOUNT_NAMES; do
    [[ -r $CX_ACCOUNT_HOMES[$k]/auth.json ]] && continue
    if _cx_confirm " Account '$k' is not signed in. Sign in now?" y; then
      if _cx_confirm "   Use the headless device-code flow instead of the browser?" n; then
        CODEX_HOME="$CX_ACCOUNT_HOMES[$k]" codex login --device-auth
      else
        CODEX_HOME="$CX_ACCOUNT_HOMES[$k]" codex login
      fi
    fi
  done

  # 3. add new accounts
  while _cx_confirm " Add a new account?" n; do
    read -r "name?   Account name (letters, digits, - _): " || break
    [[ -z $name ]] && break
    if _cx_confirm "   Use the headless device-code flow?" n; then cx add "$name" --device-auth; else cx add "$name"; fi
  done

  # 4. bind current directory
  if [[ $PWD != $HOME && ${#CX_ACCOUNT_NAMES} -gt 1 ]]; then
    read -r "name?"$'\n'" Bind ${PWD/#$HOME/~} to an account (${(j:/:)CX_ACCOUNT_NAMES}), or Enter to skip: " || name=""
    if [[ -n $name ]]; then cx bind "$name"; fi
  fi

  print
  cx ls
  print
  if _cx_confirm " Show live plan limits now (cx usage)?" n; then cx usage; fi
  print
  print " Done. Try:  cx use <name> && codex     (cx help for everything)"
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
    ls|list|status|usage)
      local want_u=0 want_v=0 a
      if [[ $sub == usage ]]; then want_u=1; fi
      for a in "${@:2}"; do
        case $a in
          -u|--usage) want_u=1 ;;
          -v|--verbose) want_v=1 ;;
          *) print "cx $sub: unknown option $a (use -v)" >&2; return 1 ;;
        esac
      done
      if (( $+commands[python3] )); then
        _cx_render $want_u $want_v
      else
        local cur k mark
        cur=$(_cx_current_account)
        print " codex accounts (* active in this shell, a auto-switch by directory)"
        for k in $CX_ACCOUNT_NAMES; do
          mark=" "
          [[ $k == $cur ]] && mark="*"
          [[ $CX_AUTO_ACTIVE == $k ]] && mark="a"
          printf ' %s %-12s %-18s %s\n' "$mark" "$k" "${CX_ACCOUNT_HOMES[$k]/#$HOME/~}" "$(_cx_account_email "$CX_ACCOUNT_HOMES[$k]")"
        done
      fi
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

    setup)
      _cx_setup
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
  cx                         list accounts, emails, plan and subscription expiry
  cx setup                   interactive first-run wizard (adopt homes, sign in, add, bind)
  cx usage [-v]              live limits (5h/7d bars); -v = detailed blocks (also: cx ls -v)
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
      'subcommands:cx command:(ls usage setup use login off add rm bind unbind binds version help)' \
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
