#!/usr/bin/env python3
"""CodeX Switch core: shell-independent logic for the `cx` command.

The per-shell wrappers (codex-switch.zsh / .bash / .fish) are thin: they run
this program and then `source` the statements it wrote to $CX_EVAL_FILE
(CODEX_HOME changes, auto-binding state, prompt marker). Everything else
(registry, bindings, rendering, login, setup wizard) lives here.

Stdlib only, Python 3.8+.
"""
import base64
import json
import math
import os
import shlex
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date

VERSION = "0.2.0"
HOME = os.path.expanduser("~")
CONFIG_DIR = os.environ.get("CX_CONFIG_DIR") or os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "codex-switch")
ACCOUNT_FILE = os.path.join(CONFIG_DIR, "accounts.tsv")
BINDING_FILE = os.path.join(CONFIG_DIR, "bindings.tsv")
SHELL = os.environ.get("CX_SHELL", "zsh")
RESERVED = {"ls", "list", "status", "usage", "setup", "use", "login", "off", "reset",
            "unset", "help", "add", "rm", "bind", "unbind", "binds", "version",
            "prompt", "apply", "names", "-h", "--help", "-v", "--version"}


# --------------------------------------------------------------------------
# Talking back to the calling shell
# --------------------------------------------------------------------------

class Emitter:
    """Collects shell statements for the wrapper to source after we exit."""

    def __init__(self):
        self.lines = []

    @staticmethod
    def _q(v):
        if SHELL == "fish":
            return "'" + v.replace("\\", "\\\\").replace("'", "\\'") + "'"
        return shlex.quote(v)

    def export(self, name, value):
        if SHELL == "fish":
            self.lines.append("set -gx %s %s" % (name, self._q(value)))
        else:
            self.lines.append("export %s=%s" % (name, self._q(value)))

    def setvar(self, name, value):
        if SHELL == "fish":
            self.lines.append("set -g %s %s" % (name, self._q(value)))
        else:
            self.lines.append("%s=%s" % (name, self._q(value)))

    def unset(self, name):
        self.lines.append("set -e %s" % name if SHELL == "fish" else "unset %s" % name)

    def flush(self):
        path = os.environ.get("CX_EVAL_FILE")
        if path and self.lines:
            with open(path, "w") as f:
                f.write("\n".join(self.lines) + "\n")


EMIT = Emitter()


def err(msg):
    print(msg, file=sys.stderr)


# --------------------------------------------------------------------------
# Registry + bindings (plain TSV files, same format as the old zsh version)
# --------------------------------------------------------------------------

def valid_name(n):
    import re
    return bool(re.match(r"^[A-Za-z0-9_-]+$", n)) and n not in RESERVED


def read_tsv(path):
    rows = []
    try:
        with open(path) as f:
            for line in f:
                line = line.rstrip("\n")
                if not line.strip() or line.startswith("#"):
                    continue
                a, _, b = line.partition("\t")
                rows.append((a, b))
    except FileNotFoundError:
        pass
    return rows


def write_tsv(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        for a, b in rows:
            f.write("%s\t%s\n" % (a, b))
    os.replace(tmp, path)


def init_registry():
    """First run: seed `default` and adopt ~/.codex-* homes that hold a sign-in."""
    if os.path.exists(ACCOUNT_FILE):
        return
    rows = [("default", os.path.join(HOME, ".codex"))]
    try:
        entries = sorted(os.listdir(HOME))
    except OSError:
        entries = []
    for e in entries:
        if not e.startswith(".codex-"):
            continue
        d = os.path.join(HOME, e)
        name = e[len(".codex-"):]
        if os.path.isfile(os.path.join(d, "auth.json")) and valid_name(name) and name != "default":
            rows.append((name, d))
    write_tsv(ACCOUNT_FILE, rows)


def accounts():
    """-> ordered list of (name, home)"""
    return read_tsv(ACCOUNT_FILE)


def homes():
    return dict(accounts())


def cwd():
    """Logical working directory ($PWD, as the shell shows it) when it is still accurate."""
    p = os.environ.get("PWD", "")
    try:
        if p and os.path.samefile(p, os.getcwd()):
            return p
    except OSError:
        pass
    return os.getcwd()


def short(path):
    return "~" + path[len(HOME):] if path == HOME or path.startswith(HOME + "/") else path


def current_account():
    ch = os.environ.get("CODEX_HOME", "")
    if not ch:
        return "default"
    for n, h in accounts():
        if h == ch:
            return n
    return "custom"


def binding_for(d):
    best_p, best_n = "", ""
    for n, p in read_tsv(BINDING_FILE):
        if (d == p or d.startswith(p.rstrip("/") + "/")) and len(p) > len(best_p):
            best_p, best_n = p, n
    return best_n


# --------------------------------------------------------------------------
# Shell state: CODEX_HOME + auto-binding + prompt marker
# --------------------------------------------------------------------------

def auto_state():
    return os.environ.get("CX_AUTO_ACTIVE", ""), os.environ.get("CX_PRE_AUTO_HOME", "")


class State:
    """Tracks the shell's CODEX_HOME / auto-binding as this process changes them."""

    def __init__(self):
        self.codex_home = os.environ.get("CODEX_HOME", "")
        self.auto, self.pre = auto_state()

    def set_home(self, home):
        self.codex_home = home or ""
        if home:
            EMIT.export("CODEX_HOME", home)
        else:
            EMIT.unset("CODEX_HOME")

    def set_auto(self, auto, pre):
        self.auto, self.pre = auto, pre
        EMIT.setvar("CX_AUTO_ACTIVE", auto)
        EMIT.setvar("_CX_PRE_AUTO_HOME", pre)

    def prompt(self):
        """Emit marker variables the wrappers use for the prompt."""
        h = homes()
        name = next((n for n, p in h.items() if p == self.codex_home), "")
        if not self.codex_home:
            kind, text = "", ""
        elif not name:
            kind, text = "custom", "[codex:custom]"
        elif self.auto and h.get(self.auto) == self.codex_home:
            kind, text = "auto", "[codex:%s:auto]" % name
        else:
            kind, text = "manual", "[codex:%s]" % name
        EMIT.setvar("CX_PROMPT_KIND", kind)
        EMIT.setvar("CX_PROMPT_NAME", name)
        EMIT.setvar("CX_PROMPT_TEXT", text)


def apply_binding(st, pwd):
    bound = binding_for(pwd)
    target = homes().get(bound) if bound else None
    if bound and target:
        if st.auto != bound:
            pre = st.codex_home if not st.auto else st.pre
            st.set_home(target)
            st.set_auto(bound, pre)
    elif st.auto:
        st.set_home(st.pre)
        st.set_auto("", "")
    st.prompt()


# --------------------------------------------------------------------------
# Rendering (account table / usage)
# --------------------------------------------------------------------------

def render(online, verbose):
    color = (sys.stdout.isatty() and not os.environ.get("NO_COLOR")) or os.environ.get("CX_COLOR") == "always"
    accts = accounts()
    cur = current_account()
    auto = os.environ.get("CX_AUTO_ACTIVE", "")

    def paint(code, s):
        return "\033[%sm%s\033[0m" % (code, s) if color and code else s

    def load(home):
        r = {"email": None, "plan": None, "until": None, "tok": {}, "state": "ok"}
        try:
            with open(os.path.join(home, "auth.json")) as f:
                d = json.load(f)
        except Exception:
            r["state"] = "none"
            return r
        t = d.get("tokens") or {}
        r["tok"] = t
        if not t.get("id_token"):
            r["state"] = "apikey" if d.get("OPENAI_API_KEY") else "none"
            return r
        try:
            p = t["id_token"].split(".")[1]
            p += "=" * (-len(p) % 4)
            c = json.loads(base64.urlsafe_b64decode(p))
        except Exception:
            r["state"] = "bad"
            return r
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

    def plain_bar(p, n):
        f = math.ceil(p / 100 * n) if p > 0 else 0
        return "▓" * f + "░" * (n - f)

    PLAN = {"pro": "36", "promax": "35", "team": "34", "plus": "32"}
    stale = [False]
    today = date.today()

    def expiry(u):
        if not u:
            return "–", "2"
        try:
            days = (date.fromisoformat(u) - today).days
        except ValueError:
            return u, None
        if days <= 7:
            stale[0] = True
            return u + " ⚠", "31"
        return u, None

    def windows(n):
        d, e = live.get(n, (None, None))
        ws = []
        if d:
            rl = d.get("rate_limit") or {}
            for k in ("primary_window", "secondary_window"):
                w = rl.get(k)
                if w:
                    ws.append((label(w["limit_window_seconds"]), w["used_percent"],
                               w["reset_after_seconds"], w["limit_window_seconds"]))
        return d, e, ws

    def who(n):
        i = info[n]
        return i["email"] or {"none": "(not signed in)", "apikey": "API key", "bad": "(unknown)"}.get(i["state"], "?")

    def mark(n):
        return paint("36", "●") if n == cur else paint("33", "◆") if n == auto else " "

    def table(rows, header):
        widths = [max(len(r[i][0]) for r in [header] + rows) for i in range(len(header))]
        for r in [header] + rows:
            out = []
            for i, (s, code) in enumerate(r):
                pad = " " * (widths[i] - len(s))
                out.append(paint(code, s) + pad if i < len(r) - 1 else paint(code, s))
            print(" " + "  ".join(out).rstrip())

    def head(*cols):
        return [(c, "2") for c in cols]

    def name_cell(n):
        return (("● " if n == cur else "◆ " if n == auto else "  ") + n, None)

    print()
    if verbose:
        sep = paint("2", " " + "─" * 58)
        for n, h in accts:
            i = info[n]
            d, e, ws = windows(n)
            plan = (d or {}).get("plan_type") or i["plan"]
            exp, ecode = expiry(i["until"])
            print(sep)
            print(" %s %s  %s  %s  %s" % (mark(n), paint("1", "%-10s" % n), who(n),
                  paint(PLAN.get(plan, "2"), plan or "–"), paint(ecode, "exp " + exp) if i["until"] else ""))
            print("   " + paint("2", short(h)))
            if e:
                print("   " + paint("31", e))
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
            d, e, ws = windows(n)
            plan = (d or {}).get("plan_type") or i["plan"]
            exp, ecode = expiry(i["until"])
            row = [name_cell(n), (plan or "–", PLAN.get(plan, "2"))]
            if e or i["state"] != "ok":
                row.append((e or who(n), "31"))
                rows.append(row)
                continue
            w5 = next((w for w in ws if w[3] < 86400), None)
            w7 = next((w for w in ws if w[3] >= 86400), None)
            for w in (w5, w7):
                row.append(("%s %3d%%" % (plain_bar(w[1], 6), w[1]), pct_code(w[1])) if w else ("–", "2"))
            row.append((left(w7[2]) if w7 else left(w5[2]) if w5 else "–", None))
            row.append((exp, ecode))
            rows.append(row)
        table(rows, head("  NAME", "PLAN", "5H", "7D", "RESET", "EXPIRES"))
    else:
        rows = []
        for n, h in accts:
            i = info[n]
            exp, ecode = expiry(i["until"])
            rows.append([name_cell(n), (who(n), None), (i["plan"] or "–", PLAN.get(i["plan"], "2")), (exp, ecode)])
        table(rows, head("  NAME", "ACCOUNT", "PLAN", "EXPIRES"))

    print()
    notes = []
    if any(n == cur for n, _ in accts) or auto:
        notes.append("● this shell  ◆ auto-bound directory")
    if stale[0]:
        notes.append("⚠ expired or within 7 days (date comes from the cached sign-in token, may be stale)")
    if not online:
        notes.append("cx usage: live limits  ·  cx ls -v: details")
    for t in notes:
        print(" " + paint("2", t))
    print()


# --------------------------------------------------------------------------
# Small interactive helpers
# --------------------------------------------------------------------------

def confirm(prompt, default="y"):
    hint = "[y/N]" if default == "n" else "[Y/n]"
    try:
        ans = input("%s %s " % (prompt, hint)).strip()
    except EOFError:
        ans = ""
        print()
    if not ans:
        ans = default
    return ans[:1].lower() == "y"


def ask(prompt):
    try:
        return input(prompt).strip()
    except EOFError:
        print()
        return ""


def run_codex_login(home, device=False):
    env = dict(os.environ, CODEX_HOME=home)
    cmd = ["codex", "login"] + (["--device-auth"] if device else [])
    try:
        return subprocess.call(cmd, env=env)
    except FileNotFoundError:
        err("cx: codex not found on PATH — install the Codex CLI first")
        return 127


def account_email(home):
    try:
        with open(os.path.join(home, "auth.json")) as f:
            d = json.load(f)
        t = (d.get("tokens") or {}).get("id_token")
        if not t:
            return "API key" if d.get("OPENAI_API_KEY") else "(no credentials)"
        p = t.split(".")[1]
        p += "=" * (-len(p) % 4)
        c = json.loads(base64.urlsafe_b64decode(p))
        return c.get("email") or c.get("preferred_username") or c.get("sub", "?")
    except FileNotFoundError:
        return "(not signed in)"
    except Exception:
        return "(unknown)"


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

def cmd_ls(args, usage=False):
    online, verbose = usage, False
    for a in args:
        if a in ("-u", "--usage"):
            online = True
        elif a in ("-v", "--verbose"):
            verbose = True
        else:
            err("cx ls: unknown option %s (use -v)" % a)
            return 1
    render(online, verbose)
    return 0


def cmd_use(args, st):
    name = args[0] if args else ""
    h = homes()
    if not name or name == "-":
        st.set_home("")
        print("codex account: default (%s/.codex)" % HOME)
    elif name in h:
        if not os.path.isdir(h[name]):
            err("cx: directory not found: %s" % h[name])
            return 1
        st.set_home("" if name == "default" else h[name])
        print("this shell -> codex account: %s" % name)
    else:
        err("cx: unknown account '%s' (accounts: %s)" % (name, " ".join(h)))
        return 1
    st.prompt()
    return 0


def cmd_off(st):
    st.set_home("")
    st.prompt()
    print("cleared CODEX_HOME; back to default account")
    return 0


def cmd_login(args):
    h = homes()
    if not args or args[0] not in h:
        err("cx: usage: cx login <%s>" % "/".join(h))
        return 1
    return run_codex_login(h[args[0]])


def cmd_add(args):
    name, home_override, do_login, device = "", "", True, False
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--home":
            if i + 1 >= len(args):
                err("cx add: --home needs a directory")
                return 1
            home_override = args[i + 1]
            i += 2
            continue
        if a == "--no-login":
            do_login = False
        elif a == "--device-auth":
            device = True
        elif a.startswith("-"):
            err("cx add: unknown flag %s" % a)
            return 1
        elif not name:
            name = a
        else:
            err("cx add: unexpected argument %s" % a)
            return 1
        i += 1
    if not name:
        err("usage: cx add <name> [--home DIR] [--no-login] [--device-auth]")
        return 1
    if not valid_name(name):
        err("cx: name must match [A-Za-z0-9_-] and not collide with a command: %s" % name)
        return 1
    h = homes()
    if name in h:
        err("cx: account '%s' already exists: %s" % (name, h[name]))
        return 1
    home = os.path.expanduser(home_override) if home_override else os.path.join(HOME, ".codex-%s" % name)
    for k, p in h.items():
        if p == home:
            err("cx: directory already registered as account '%s': %s" % (k, home))
            return 1
    os.makedirs(home, exist_ok=True)
    if do_login and not os.path.isfile(os.path.join(home, "auth.json")):
        print("Complete the sign-in in your browser (account: %s)..." % name)
        if run_codex_login(home, device) != 0:
            err("cx: login failed; account not registered (directory kept: %s)" % home)
            return 1
    write_tsv(ACCOUNT_FILE, accounts() + [(name, home)])
    print("added account: %s -> %s" % (name, home))
    if not do_login:
        print("not signed in yet: run  cx login %s" % name)
    return 0


def cmd_rm(args):
    name = args[0] if args else ""
    purge = len(args) > 1 and args[1] == "--purge"
    if not name:
        err("usage: cx rm <name> [--purge]")
        return 1
    if name == "default":
        err("cx: default is built-in and cannot be removed")
        return 1
    h = homes()
    if name not in h:
        err("cx: unknown account '%s' (accounts: %s)" % (name, " ".join(h)))
        return 1
    home = h[name]
    if home == os.environ.get("CODEX_HOME", ""):
        err("cx: '%s' is active in this shell; run 'cx use -' first" % name)
        return 1
    write_tsv(ACCOUNT_FILE, [(n, p) for n, p in accounts() if n != name])
    if os.path.exists(BINDING_FILE):
        write_tsv(BINDING_FILE, [(n, p) for n, p in read_tsv(BINDING_FILE) if n != name])
    print("removed account from registry: %s" % name)
    if not purge and os.path.isdir(home) and sys.stdin.isatty():
        purge = confirm("Also delete data directory %s ? This cannot be undone" % home, "n")
    if purge:
        import shutil
        shutil.rmtree(home, ignore_errors=True)
        print("deleted data directory: %s" % home)
    elif os.path.isdir(home):
        print("data directory kept: %s (delete it yourself, or re-register with cx add)" % home)
    return 0


def cmd_bind(args, st):
    name = args[0] if args else ""
    d = cwd()
    if not name:
        if not st.codex_home:
            err("cx: currently on default; use 'cx bind <name>' or 'cx use <name>' first")
            return 1
        name = current_account()
    h = homes()
    if name not in h:
        err("cx: unknown account '%s' (accounts: %s)" % (name, " ".join(h)))
        return 1
    rows, existed = [], False
    for n, p in read_tsv(BINDING_FILE):
        if p == d:
            existed = True
            rows.append((name, d))
        else:
            rows.append((n, p))
    if not existed:
        rows.append((name, d))
    write_tsv(BINDING_FILE, rows)
    print("bound: %s -> %s (auto-switch in this directory and subdirectories)" % (d, name))
    if existed:
        print("(replaced previous binding for this directory)")
    apply_binding(st, d)
    return 0


def cmd_unbind(args, st):
    d = args[0] if args else cwd()
    rows = read_tsv(BINDING_FILE)
    if not rows:
        print("cx: no project bindings")
        return 0
    kept = [(n, p) for n, p in rows if p != d]
    if len(kept) == len(rows):
        print("cx: no binding for %s" % d)
        return 0
    write_tsv(BINDING_FILE, kept)
    print("unbound: %s" % d)
    apply_binding(st, cwd())
    return 0


def cmd_binds():
    rows = read_tsv(BINDING_FILE)
    if not rows:
        print("(no project bindings yet — run 'cx bind <name>' inside a project directory)")
        return 0
    pwd = cwd()
    cur = binding_for(pwd)
    print(" account       project directory (* active here)")
    for n, p in rows:
        active = n == cur and (pwd == p or pwd.startswith(p.rstrip("/") + "/"))
        print(" %s%-12s %s" % ("* " if active else "  ", n, p))
    return 0


HELP = """  cx                         list accounts, emails, plan and subscription expiry
  cx setup                   interactive first-run wizard (adopt homes, sign in, add, bind)
  cx usage [-v]              live limits (5h/7d bars); -v = detailed blocks (also: cx ls -v)
  cx use <name>              switch this shell to <name>
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
  cx prompt                  print the prompt marker (also in $CX_PROMPT_TEXT)
  cx version                 print CodeX Switch version
"""


def cmd_help():
    print("cx — CodeX Switch: parallel multi-account manager for Codex CLI")
    print(HELP)
    print("  accounts: %s" % " ".join(homes()))
    print("  files:    %s" % ACCOUNT_FILE)
    print("            %s" % BINDING_FILE)
    return 0


def cmd_setup(st):
    print("\033[1m CodeX Switch setup\033[0m" if sys.stdout.isatty() else " CodeX Switch setup")
    print()
    import shutil
    codex = shutil.which("codex")
    print(" ✓ codex found: %s" % codex if codex else
          " ! codex not found on PATH — install the Codex CLI first (accounts can still be registered)")
    print(" ✓ python3 %s (this tool's core)" % sys.version.split()[0])
    print()

    h = homes()
    registered = set(h.values())
    try:
        entries = sorted(os.listdir(HOME))
    except OSError:
        entries = []
    for e in entries:
        d = os.path.join(HOME, e)
        if not (e.startswith(".codex-") and os.path.isdir(d) and os.path.isfile(os.path.join(d, "auth.json"))):
            continue
        if d in registered:
            continue
        name = e[len(".codex-"):]
        if not valid_name(name) or name in homes():
            print(" - skipping %s: '%s' is not a usable account name (register it with: cx add <name> --home %s --no-login)"
                  % (short(d), name, short(d)))
            continue
        if confirm(" Found signed-in home %s (%s). Register as '%s'?" % (short(d), account_email(d), name), "y"):
            write_tsv(ACCOUNT_FILE, accounts() + [(name, d)])

    for n, p in accounts():
        if os.path.isfile(os.path.join(p, "auth.json")):
            continue
        if confirm(" Account '%s' is not signed in. Sign in now?" % n, "y"):
            dev = confirm("   Use the headless device-code flow instead of the browser?", "n")
            run_codex_login(p, dev)

    while confirm(" Add a new account?", "n"):
        name = ask("   Account name (letters, digits, - _): ")
        if not name:
            break
        dev = confirm("   Use the headless device-code flow?", "n")
        cmd_add([name] + (["--device-auth"] if dev else []))

    names = [n for n, _ in accounts()]
    if cwd() != HOME and len(names) > 1:
        print()
        name = ask(" Bind %s to an account (%s), or Enter to skip: " % (short(cwd()), "/".join(names)))
        if name:
            cmd_bind([name], st)

    print()
    render(False, False)
    if confirm(" Show live plan limits now (cx usage)?", "n"):
        render(True, False)
    print()
    print(" Done. Try:  cx use <name> && codex     (cx help for everything)")
    return 0


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------

def main(argv):
    init_registry()
    st = State()
    sub = argv[0] if argv else "ls"
    rest = argv[1:]
    rc = 0
    if sub in ("ls", "list", "status"):
        rc = cmd_ls(rest)
    elif sub == "usage":
        rc = cmd_ls(rest, usage=True)
    elif sub == "use":
        rc = cmd_use(rest, st)
    elif sub in ("off", "reset", "unset"):
        rc = cmd_off(st)
    elif sub == "login":
        rc = cmd_login(rest)
    elif sub == "setup":
        rc = cmd_setup(st)
    elif sub == "add":
        rc = cmd_add(rest)
    elif sub == "rm":
        rc = cmd_rm(rest)
    elif sub == "bind":
        rc = cmd_bind(rest, st)
    elif sub == "unbind":
        rc = cmd_unbind(rest, st)
    elif sub == "binds":
        rc = cmd_binds()
    elif sub in ("version", "-v", "--version"):
        print("CodeX Switch %s" % VERSION)
    elif sub in ("help", "-h", "--help"):
        rc = cmd_help()
    elif sub == "prompt":
        h = homes()
        name = next((n for n, p in h.items() if p == st.codex_home), "")
        if st.codex_home:
            print("[codex:%s%s]" % (name or "custom", ":auto" if st.auto and h.get(st.auto) == st.codex_home else ""))
    elif sub == "apply":
        apply_binding(st, rest[0] if rest else cwd())
    elif sub == "names":
        print("\n".join(n for n, _ in accounts()))
    else:
        h = homes()
        if sub in h:
            env = dict(os.environ, CODEX_HOME=h[sub])
            EMIT.flush()
            try:
                os.execvpe("codex", ["codex"] + rest, env)
            except FileNotFoundError:
                err("cx: codex not found on PATH")
                return 127
        err("cx: unknown command/account '%s' (cx help)" % sub)
        rc = 1
    EMIT.flush()
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
