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
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date

VERSION = "0.3.1"
HOME = os.path.expanduser("~")
CONFIG_DIR = os.environ.get("CX_CONFIG_DIR") or os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "codex-switch")
ACCOUNT_FILE = os.path.join(CONFIG_DIR, "accounts.tsv")
BINDING_FILE = os.path.join(CONFIG_DIR, "bindings.tsv")
CLAUDE_FILE = os.path.join(CONFIG_DIR, "claude-accounts.tsv")
SHELL = os.environ.get("CX_SHELL", "zsh")
RESERVED = {"ls", "list", "status", "usage", "setup", "use", "login", "off", "reset",
            "unset", "help", "add", "rm", "bind", "unbind", "binds", "version",
            "prompt", "apply", "names", "hook", "-h", "--help", "-v", "--version"}


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
    """-> ordered list of Codex (name, home)"""
    return read_tsv(ACCOUNT_FILE)


def homes():
    return dict(accounts())


# Claude Code accounts live in their own registry file (phase 1: subscription
# logins, isolated through CLAUDE_CONFIG_DIR). Names are unique across both.
def claude_accounts():
    return read_tsv(CLAUDE_FILE)


def registry(kind):
    return dict(claude_accounts() if kind == "claude" else accounts())


def kind_of(name):
    if name in homes():
        return "codex"
    if name in dict(claude_accounts()):
        return "claude"
    return None


def all_accounts():
    """-> [(name, home, kind)] Codex first, then Claude."""
    return [(n, h, "codex") for n, h in accounts()] + [(n, h, "claude") for n, h in claude_accounts()]


VARS = {"codex": "CODEX_HOME", "claude": "CLAUDE_CONFIG_DIR"}
# kind -> (env var the wrapper passes in, shell variable we set, env var for the pre-auto home, shell var for it)
AUTO_VARS = {
    "codex": ("CX_AUTO_ACTIVE", "CX_AUTO_ACTIVE", "CX_PRE_AUTO_HOME", "_CX_PRE_AUTO_HOME"),
    "claude": ("CX_AUTO_CLAUDE", "CX_AUTO_CLAUDE", "CX_PRE_AUTO_CLAUDE", "_CX_PRE_AUTO_CLAUDE"),
}

# Variables that outrank (or redirect) a Claude subscription login. See
# https://code.claude.com/docs/en/authentication#authentication-precedence
CLAUDE_OVERRIDES = ("ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN",
                    "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY")
OFFICIAL_URL = "https://api.anthropic.com"


def claude_clean_env(home):
    """Environment for running `claude` on a subscription account in `home`.

    Strips every inherited provider/auth override so the account's own login is
    used. A set ANTHROPIC_BASE_URL is pinned to the official endpoint rather
    than removed: with a local proxy configured, merely unsetting it can still
    route requests through the proxy.
    """
    env = {k: v for k, v in os.environ.items()
           if not (k.startswith("ANTHROPIC_") or k.startswith("CLAUDE_CODE_USE_")
                   or k.startswith("CLAUDE_CODE_GATEWAY_") or k == "CLAUDE_CODE_OAUTH_TOKEN")}
    if "ANTHROPIC_BASE_URL" in os.environ:
        env["ANTHROPIC_BASE_URL"] = OFFICIAL_URL
    env["CLAUDE_CONFIG_DIR"] = home
    return env


def claude_usage_cache(home):
    """-> dict from the status-line relay's cache (see cx_statusline.py) or None."""
    try:
        with open(os.path.join(home, ".cx-usage.json")) as f:
            return json.load(f)
    except Exception:
        return None


def claude_status(home):
    """-> dict from `claude auth status` for the account in `home`, or {"error": ...}."""
    try:
        r = subprocess.run(["claude", "auth", "status", "--json"], env=claude_clean_env(home),
                           capture_output=True, text=True, timeout=20)
        return json.loads(r.stdout)
    except FileNotFoundError:
        return {"error": "claude not found on PATH"}
    except Exception as e:
        return {"error": "claude auth status failed: %s" % e}


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


def current_account(kind="codex"):
    """Name of the account active in this shell for `kind`; 'default'/None when unset, 'custom' if unregistered."""
    ch = os.environ.get(VARS[kind], "")
    if not ch:
        return "default" if kind == "codex" else None
    for n, h in registry(kind).items():
        if h == ch:
            return n
    return "custom"


def binding_for(d, kind="codex"):
    best_p, best_n = "", ""
    reg = registry(kind)
    for n, p in read_tsv(BINDING_FILE):
        if n in reg and (d == p or d.startswith(p.rstrip("/") + "/")) and len(p) > len(best_p):
            best_p, best_n = p, n
    return best_n


# --------------------------------------------------------------------------
# Shell state: CODEX_HOME / CLAUDE_CONFIG_DIR + auto-binding + prompt marker
# --------------------------------------------------------------------------

class State:
    """Tracks the shell's account variables / auto-binding as this process changes them."""

    def __init__(self):
        self.home = {k: os.environ.get(v, "") for k, v in VARS.items()}
        self.auto = {k: os.environ.get(AUTO_VARS[k][0], "") for k in VARS}
        self.pre = {k: os.environ.get(AUTO_VARS[k][2], "") for k in VARS}

    def set_home(self, kind, home):
        self.home[kind] = home or ""
        if home:
            EMIT.export(VARS[kind], home)
        else:
            EMIT.unset(VARS[kind])

    def set_auto(self, kind, auto, pre):
        self.auto[kind], self.pre[kind] = auto, pre
        EMIT.setvar(AUTO_VARS[kind][1], auto)
        EMIT.setvar(AUTO_VARS[kind][3], pre)

    def prompt_info(self):
        """-> (kind, name, text): kind is ''|manual|auto|custom."""
        parts, kinds, first = [], set(), ""
        for kind in ("codex", "claude"):
            home = self.home[kind]
            if not home:
                continue
            reg = registry(kind)
            name = next((n for n, p in reg.items() if p == home), "")
            first = first or name
            if not name:
                kinds.add("custom")
                parts.append("%s:custom" % kind)
            elif self.auto[kind] and reg.get(self.auto[kind]) == home:
                kinds.add("auto")
                parts.append("%s:%s:auto" % (kind, name))
            else:
                kinds.add("manual")
                parts.append("%s:%s" % (kind, name))
        kind = "auto" if "auto" in kinds else "custom" if "custom" in kinds else "manual" if kinds else ""
        return kind, first, ("[%s]" % " ".join(parts)) if parts else ""

    def prompt(self):
        """Emit marker variables the wrappers use for the prompt."""
        kind, name, text = self.prompt_info()
        EMIT.setvar("CX_PROMPT_KIND", kind)
        EMIT.setvar("CX_PROMPT_NAME", name)
        EMIT.setvar("CX_PROMPT_TEXT", text)


def apply_binding(st, pwd):
    for kind in ("codex", "claude"):
        bound = binding_for(pwd, kind)
        target = registry(kind).get(bound) if bound else None
        if bound and target:
            if st.auto[kind] != bound:
                pre = st.home[kind] if not st.auto[kind] else st.pre[kind]
                st.set_home(kind, target)
                st.set_auto(kind, bound, pre)
        elif st.auto[kind]:
            st.set_home(kind, st.pre[kind])
            st.set_auto(kind, "", "")
    st.prompt()


# --------------------------------------------------------------------------
# Rendering (account table / usage)
# --------------------------------------------------------------------------

def render(online, verbose):
    color = (sys.stdout.isatty() and not os.environ.get("NO_COLOR")) or os.environ.get("CX_COLOR") == "always"
    all_acc = all_accounts()
    accts = [(n, h) for n, h, _ in all_acc]
    kind = {n: k for n, _, k in all_acc}
    has_claude = any(k == "claude" for k in kind.values())
    cur = {"codex": current_account("codex"), "claude": current_account("claude")}
    auto = {"codex": os.environ.get("CX_AUTO_ACTIVE", ""), "claude": os.environ.get("CX_AUTO_CLAUDE", "")}

    def is_cur(n):
        return cur[kind[n]] == n

    def is_auto(n):
        return bool(auto[kind[n]]) and auto[kind[n]] == n

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

    def load_claude(home):
        st = claude_status(home)
        r = {"email": None, "plan": None, "until": None, "tok": {}, "state": "ok"}
        if st.get("error"):
            r["state"], r["email"] = "bad", st["error"]
        elif not st.get("loggedIn"):
            r["state"] = "none"
        else:
            r["email"] = st.get("email") or st.get("orgName") or "(signed in)"
            r["plan"] = st.get("subscriptionType")
        return r

    claude_age = {}
    info = {n: load(h) for n, h in accts if kind[n] == "codex"}
    with ThreadPoolExecutor(max_workers=8) as ex:
        cfuts = {n: ex.submit(load_claude, h) for n, h in accts if kind[n] == "claude"}
        info.update({n: f.result() for n, f in cfuts.items()})
    live = {}
    if online:
        with ThreadPoolExecutor(max_workers=8) as ex:
            futs = {n: ex.submit(fetch, info[n]["tok"]) for n, _ in accts
                    if kind[n] == "codex" and info[n]["state"] == "ok"}
            live = {n: f.result() for n, f in futs.items()}
        # Claude Code windows come from the status-line relay's cache, not the network.
        # A window is dropped once its reset time has passed (it no longer applies).
        now = time.time()
        for n, h in accts:
            if kind[n] != "claude":
                continue
            c = claude_usage_cache(h) or {}
            ws = []
            for key, secs in (("five_hour", 18000), ("seven_day", 604800)):
                w = c.get(key)
                if isinstance(w, dict) and w.get("resets_at") and w["resets_at"] > now:
                    ws.append({"limit_window_seconds": secs, "used_percent": int(round(float(w["used_percentage"]))),
                               "reset_after_seconds": int(w["resets_at"] - now)})
            claude_age[n] = (int(now - c["updated_at"]) if c.get("updated_at") else None) if c else None
            if ws:
                live[n] = ({"rate_limit": {"primary_window": ws[0], "secondary_window": ws[1] if len(ws) > 1 else None}}, None)

    def ago(secs):
        return "%dm" % (secs // 60) if secs < 3600 else "%dh%dm" % (secs // 3600, secs % 3600 // 60) if secs < 86400 else "%dd" % (secs // 86400)

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

    PLAN = {"pro": "36", "promax": "35", "max": "35", "team": "34", "enterprise": "34", "plus": "32"}
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
        return paint("36", "●") if is_cur(n) else paint("33", "◆") if is_auto(n) else " "

    def table(rows, header):
        # A short row (e.g. an error message in place of the usage columns) spills
        # its last cell to the right; it must not widen the column it starts in.
        def counts(r, i):
            return i < len(r) and (len(r) == len(header) or i < len(r) - 1)
        widths = [max([len(r[i][0]) for r in [header] + rows if counts(r, i)] or [0]) for i in range(len(header))]
        for r in [header] + rows:
            out = []
            for i, (s, code) in enumerate(r):
                pad = " " * (widths[i] - len(s))
                out.append(paint(code, s) + pad if i < len(r) - 1 else paint(code, s))
            print(" " + "  ".join(out).rstrip())

    def head(*cols):
        return [(c, "2") for c in cols]

    def name_cell(n):
        return (("● " if is_cur(n) else "◆ " if is_auto(n) else "  ") + n, None)

    def tool_cells(n):
        return [(kind[n], "2")] if has_claude else []

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
            print("   " + paint("2", short(h) + ("  (claude)" if kind[n] == "claude" else "")))
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
            row = [name_cell(n)] + tool_cells(n) + [(plan or "–", PLAN.get(plan, "2"))]
            if kind[n] == "claude" and i["state"] == "ok" and not ws:
                row += [("–", "2"), ("–", "2"), ("–", "2"), ("–", "2")]
                rows.append(row)
                continue
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
        table(rows, head(*(["  NAME"] + (["TOOL"] if has_claude else []) + ["PLAN", "5H", "7D", "RESET", "EXPIRES"])))
    else:
        rows = []
        for n, h in accts:
            i = info[n]
            exp, ecode = expiry(i["until"])
            rows.append([name_cell(n)] + tool_cells(n) + [(who(n), None), (i["plan"] or "–", PLAN.get(i["plan"], "2")), (exp, ecode)])
        table(rows, head(*(["  NAME"] + (["TOOL"] if has_claude else []) + ["ACCOUNT", "PLAN", "EXPIRES"])))

    print()
    notes = []
    if any(is_cur(n) or is_auto(n) for n, _ in accts):
        notes.append("● this shell  ◆ auto-bound directory")
    if online and has_claude:
        for n, _ in accts:
            if kind[n] != "claude":
                continue
            if claude_age.get(n) is not None:
                notes.append("%s: Claude usage as of %s ago (from its last session)" % (n, ago(claude_age[n])))
            else:
                notes.append("%s: no Claude usage yet — run 'cx hook install %s', then use claude once" % (n, n))
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


def claude_override_warning(home):
    """Warn when inherited variables would outrank the Claude account we just selected."""
    present = [v for v in CLAUDE_OVERRIDES if os.environ.get(v)]
    if os.environ.get("ANTHROPIC_BASE_URL"):
        present.append("ANTHROPIC_BASE_URL")
    if present:
        err("cx: warning: %s %s set in this shell and may override or redirect the account's own login "
            "(unset them, or use the one-shot form 'cx <name> ...', which cleans them)"
            % (", ".join(present), "is" if len(present) == 1 else "are"))


def cmd_use(args, st):
    name = args[0] if args else ""
    if not name or name == "-":
        st.set_home("codex", "")
        st.set_home("claude", "")
        print("codex account: default (%s/.codex); claude: cleared" % HOME)
        st.prompt()
        return 0
    kind = kind_of(name)
    if kind is None:
        names = [n for n, _, _ in all_accounts()]
        err("cx: unknown account '%s' (accounts: %s)" % (name, " ".join(names)))
        return 1
    home = registry(kind)[name]
    if not os.path.isdir(home):
        err("cx: directory not found: %s" % home)
        return 1
    if kind == "codex":
        st.set_home("codex", "" if name == "default" else home)
    else:
        st.set_home("claude", home)
        claude_override_warning(home)
    print("this shell -> %s account: %s" % (kind, name))
    st.prompt()
    return 0


def cmd_off(st):
    st.set_home("codex", "")
    st.set_home("claude", "")
    st.prompt()
    print("cleared CODEX_HOME and CLAUDE_CONFIG_DIR; back to default accounts")
    return 0


def run_claude_login(home):
    try:
        return subprocess.call(["claude", "auth", "login", "--claudeai"], env=claude_clean_env(home))
    except FileNotFoundError:
        err("cx: claude not found on PATH — install Claude Code first")
        return 127


def cmd_login(args):
    names = [n for n, _, _ in all_accounts()]
    if not args or kind_of(args[0]) is None:
        err("cx: usage: cx login <%s>" % "/".join(names))
        return 1
    kind = kind_of(args[0])
    home = registry(kind)[args[0]]
    return run_claude_login(home) if kind == "claude" else run_codex_login(home)


def cmd_add(args):
    name, home_override, do_login, device, claude = "", "", True, False, False
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
        elif a == "--claude":
            claude = True
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
        err("usage: cx add <name> [--claude] [--home DIR] [--no-login] [--device-auth]")
        return 1
    if claude and device:
        err("cx add: --device-auth is Codex-only (Claude Code signs in through the browser)")
        return 1
    if not valid_name(name):
        err("cx: name must match [A-Za-z0-9_-] and not collide with a command: %s" % name)
        return 1
    existing = kind_of(name)
    if existing:
        err("cx: account '%s' already exists (%s): %s" % (name, existing, registry(existing)[name]))
        return 1
    if home_override:
        home = os.path.abspath(os.path.expanduser(home_override))
    else:
        home = os.path.join(HOME, (".claude-%s" if claude else ".codex-%s") % name)
    for n, p, k in all_accounts():
        if p == home:
            err("cx: directory already registered as account '%s': %s" % (n, home))
            return 1
    os.makedirs(home, exist_ok=True)
    if claude:
        signed_in = claude_status(home).get("loggedIn")
        if do_login and not signed_in:
            print("Complete the sign-in in your browser (Claude account: %s)..." % name)
            if run_claude_login(home) != 0:
                err("cx: login failed; account not registered (directory kept: %s)" % home)
                return 1
        write_tsv(CLAUDE_FILE, claude_accounts() + [(name, home)])
    else:
        if do_login and not os.path.isfile(os.path.join(home, "auth.json")):
            print("Complete the sign-in in your browser (account: %s)..." % name)
            if run_codex_login(home, device) != 0:
                err("cx: login failed; account not registered (directory kept: %s)" % home)
                return 1
        write_tsv(ACCOUNT_FILE, accounts() + [(name, home)])
    print("added %saccount: %s -> %s" % ("claude " if claude else "", name, home))
    signed_in = (claude_status(home).get("loggedIn") if claude
                 else os.path.isfile(os.path.join(home, "auth.json")))
    if not signed_in:
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
    kind = kind_of(name)
    if kind is None:
        names = [n for n, _, _ in all_accounts()]
        err("cx: unknown account '%s' (accounts: %s)" % (name, " ".join(names)))
        return 1
    home = registry(kind)[name]
    if home == os.environ.get(VARS[kind], ""):
        err("cx: '%s' is active in this shell; run 'cx use -' first" % name)
        return 1
    reg_file = CLAUDE_FILE if kind == "claude" else ACCOUNT_FILE
    write_tsv(reg_file, [(n, p) for n, p in read_tsv(reg_file) if n != name])
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
        active = [k for k in ("codex", "claude") if st.home[k]]
        if not active:
            err("cx: currently on default; use 'cx bind <name>' or 'cx use <name>' first")
            return 1
        if len(active) > 1:
            err("cx: both a codex and a claude account are active; name one: cx bind <name>")
            return 1
        name = current_account(active[0])
    kind = kind_of(name)
    if kind is None:
        names = [n for n, _, _ in all_accounts()]
        err("cx: unknown account '%s' (accounts: %s)" % (name, " ".join(names)))
        return 1
    rows, existed = [], False
    for n, p in read_tsv(BINDING_FILE):
        if p == d and kind_of(n) == kind:
            existed = True
            rows.append((name, d))
        else:
            rows.append((n, p))
    if not existed:
        rows.append((name, d))
    write_tsv(BINDING_FILE, rows)
    print("bound: %s -> %s (auto-switch in this directory and subdirectories)" % (d, name))
    if existed:
        print("(replaced previous %s binding for this directory)" % kind)
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
    here = {binding_for(pwd, k) for k in ("codex", "claude")} - {""}
    print(" account       project directory (* active here)")
    for n, p in rows:
        active = n in here and (pwd == p or pwd.startswith(p.rstrip("/") + "/"))
        tag = "  (claude)" if kind_of(n) == "claude" else ""
        print(" %s%-12s %s%s" % ("* " if active else "  ", n, p, tag))
    return 0


def hook_script():
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "cx_statusline.py")


def unwrap_status_command(cmd):
    """If `cmd` is our relay, return the wrapped original command ('' if none); else None."""
    try:
        parts = shlex.split(cmd)
    except ValueError:
        return None
    if len(parts) >= 2 and os.path.basename(parts[1]) == "cx_statusline.py":
        rest = parts[2:]
        if rest[:1] == ["--"]:
            rest = rest[1:]
        return rest[0] if rest else ""
    return None


def wrap_status_command(orig):
    base = "python3 %s" % shlex.quote(hook_script())
    return "%s -- %s" % (base, shlex.quote(orig)) if orig else base


def cmd_hook(args):
    """cx hook install|remove|status <claude account> [--dry-run]"""
    usage = "usage: cx hook install|remove|status <claude-account> [--dry-run] [--yes]"
    dry, yes = "--dry-run" in args, "--yes" in args
    args = [a for a in args if a not in ("--dry-run", "--yes")]
    if len(args) != 2 or args[0] not in ("install", "remove", "status"):
        err(usage)
        return 1
    action, name = args
    if kind_of(name) != "claude":
        err("cx: '%s' is not a Claude account (cx add --claude <name>)" % name)
        return 1
    home = registry("claude")[name]
    path = os.path.realpath(os.path.join(home, "settings.json"))
    try:
        with open(path) as f:
            settings = json.load(f)
    except FileNotFoundError:
        settings = {}
    except ValueError as e:
        err("cx: cannot parse %s: %s" % (path, e))
        return 1
    sl = settings.get("statusLine") if isinstance(settings.get("statusLine"), dict) else {}
    cur = sl.get("command", "") or ""
    orig = unwrap_status_command(cur)
    cache = claude_usage_cache(home)

    if action == "status":
        print("settings: %s" % path)
        print("relay:    %s" % ("installed" if orig is not None else "not installed"))
        print("wraps:    %s" % ((orig or "(nothing)") if orig is not None else (cur or "(no status line configured)")))
        if cache and cache.get("updated_at"):
            print("cache:    updated %ds ago" % int(time.time() - cache["updated_at"]))
        else:
            print("cache:    none yet (use claude once with the relay installed)")
        return 0

    if action == "install":
        if orig is not None:
            print("already installed for %s" % name)
            return 0
        new_cmd = wrap_status_command(cur)
        new_sl = dict(sl, type="command", command=new_cmd)
        if not cur:
            print("note: '%s' has no status line. Installing adds a minimal one (model, context, 5h/7d)." % name)
            print("      Claude Code hides most footer keyboard hints (esc to interrupt, ? for shortcuts)")
            print("      while any status line is configured. 'cx hook remove %s' undoes this." % name)
    else:
        if orig is None:
            print("not installed for %s" % name)
            return 0
        new_sl = dict(sl)
        if orig:
            new_sl["command"] = orig
        else:
            new_sl = None

    print("%s: %s" % (path, "statusLine.command"))
    print("  - %s" % (cur or "(none)"))
    print("  + %s" % ((new_sl or {}).get("command") or "(statusLine removed)"))
    if dry:
        print("(dry run, nothing written)")
        return 0
    if action == "install" and not cur and not yes:
        if not sys.stdin.isatty():
            err("cx: refusing to add a status line without confirmation (re-run with --yes)")
            return 1
        if not confirm("Add a minimal status line to '%s'?" % name, "n"):
            print("cancelled")
            return 1
    import shutil
    if os.path.exists(path):
        backup = "%s.cx-bak-%d" % (path, int(time.time()))
        shutil.copy2(path, backup)
        print("backup: %s" % backup)
    if new_sl is None:
        settings.pop("statusLine", None)
    else:
        settings["statusLine"] = new_sl
    tmp = path + ".cx.tmp"
    with open(tmp, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if os.path.exists(path):
        os.chmod(tmp, os.stat(path).st_mode & 0o777)
    os.replace(tmp, path)
    print("%s for %s" % ("installed" if action == "install" else "removed", name))
    return 0


HELP = """  cx                         list accounts, emails, plan and subscription expiry
  cx setup                   interactive first-run wizard (adopt homes, sign in, add, bind)
  cx usage [-v]              live limits (5h/7d bars); -v = detailed blocks (also: cx ls -v)
  cx use <name>              switch this shell to <name> (sets CODEX_HOME or CLAUDE_CONFIG_DIR)
  cx use -                   switch this shell back to default
  cx <name> [args]           one-shot: runs codex (or claude, for a Claude account)
                             under that account, e.g.  cx work exec "..."
  cx login <name>            run codex login for one account
  cx off                     clear the switch
  cx add <name>              create a Codex account (new CODEX_HOME + sign-in)
      [--home DIR] [--no-login] [--device-auth]
  cx add --claude <name>     create a Claude Code subscription account
      (own CLAUDE_CONFIG_DIR ~/.claude-<name>; sign-in via claude auth login)
  cx rm <name> [--purge]     unregister (keeps data unless confirmed/--purge)
  cx bind [name]             bind current directory (default: current account)
  cx unbind [dir]            remove a directory binding (default: current dir)
  cx binds                   list project bindings
  cx hook install <claude>   relay Claude Code's status-line rate_limits into a cache so
                             cx usage can show 5h/7d (also: hook remove|status, --dry-run;
                             an account with no status line needs --yes or a confirmation)
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
    elif sub == "hook":
        rc = cmd_hook(rest)
    elif sub == "prompt":
        print(st.prompt_info()[2])
    elif sub == "apply":
        apply_binding(st, rest[0] if rest else cwd())
    elif sub == "names":
        print("\n".join(n for n, _, _ in all_accounts()))
    else:
        kind = kind_of(sub)
        if kind:
            home = registry(kind)[sub]
            EMIT.flush()
            if kind == "claude":
                env, argv = claude_clean_env(home), ["claude"] + rest
            else:
                env, argv = dict(os.environ, CODEX_HOME=home), ["codex"] + rest
            try:
                os.execvpe(argv[0], argv, env)
            except FileNotFoundError:
                err("cx: %s not found on PATH" % argv[0])
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
