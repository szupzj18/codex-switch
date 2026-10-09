"""Zorua providers: third-party endpoints for Claude Code and Codex (base URL + key + model).

Every provider belongs to one agent ("kind"), so a shell can have one Claude provider and
one Codex provider active at the same time.

Claude: a provider is the `env` block Claude Code should run with. Launching goes through
`claude --settings <file>`: a plain ANTHROPIC_BASE_URL in the shell loses to the `env` block
in ~/.claude/settings.json, while --settings outranks it. The file is written 0600 so the key
never shows up in `ps`.

Codex: a provider is a [model_providers.*] table plus a model, handed to `codex -c ...`
overrides; the key travels in the ZORUA_CODEX_KEY environment variable (env_key), never argv.

Stdlib only; no knowledge of the shell wrappers. Functions take the config
directory explicitly so zorua_core.py stays the only owner of its location.
"""
import json
import os
import re
import sqlite3
import urllib.error
import urllib.request

# Roles accepted by `--model ROLE=ID`.
MODEL_VARS = {
    "default": "ANTHROPIC_MODEL",
    "opus": "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "sonnet": "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "haiku": "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    "subagent": "CLAUDE_CODE_SUBAGENT_MODEL",
}
SECRET_MARKS = ("TOKEN", "KEY", "SECRET", "PASSWORD")
# Inherited variables that would outrank or redirect a provider's own settings.
_STRIP_PREFIXES = ("ANTHROPIC_", "CLAUDE_CODE_USE_", "CLAUDE_CODE_GATEWAY_")
_STRIP_NAMES = ("CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_SUBAGENT_MODEL")


def _file(cfg):
    return os.path.join(cfg, "providers.json")


def load(cfg):
    """-> {name: {"env": {...}}}"""
    try:
        with open(_file(cfg)) as f:
            return json.load(f).get("providers", {})
    except FileNotFoundError:
        return {}


def _write_private(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def save(cfg, providers):
    _write_private(_file(cfg), json.dumps({"providers": providers}, indent=2) + "\n")


AGENTS = ("claude", "codex")
CODEX_KEY_VAR = "ZORUA_CODEX_KEY"


def agent(p):
    return p.get("kind", "claude")


def endpoint(p):
    return host(p["env"]) if agent(p) == "claude" else host({"ANTHROPIC_BASE_URL": p.get("base_url", "")})


def secret(p):
    """-> the provider's key (empty when it has none)"""
    if agent(p) == "claude":
        return p["env"].get(key_var(p["env"]), "")
    return p.get("key", "")


def model_summary(p):
    cat = models(p)
    if cat:
        return "%d model%s" % (len(cat), "" if len(cat) == 1 else "s")
    if agent(p) == "claude":
        return ",".join(r for r, v in MODEL_VARS.items() if v in p["env"]) or "-"
    return p.get("model") or "-"


# --------------------------------------------------------------------------
# Model catalog: a provider can know many models; one is picked per shell
# --------------------------------------------------------------------------

def models(p):
    """-> {alias: model id}, in the order they were added"""
    return dict(p.get("models") or {})


def make_alias(model_id, taken=()):
    """Short typeable name for a model id: the last path segment without a [1M]-style suffix."""
    base = re.sub(r"\[[^\]]*\]$", "", model_id.rstrip("/")).rsplit("/", 1)[-1]
    alias = re.sub(r"[^A-Za-z0-9_.-]+", "-", base).strip("-").lower() or "model"
    cand, n = alias, 2
    while cand in taken:
        cand, n = "%s-%d" % (alias, n), n + 1
    return cand


def add_models(p, ids):
    """Add model ids (skipping ones already listed); -> number added"""
    cat = models(p)
    known = set(cat.values())
    added = 0
    for mid in ids:
        if mid and mid not in known:
            cat[make_alias(mid, cat)] = mid
            known.add(mid)
            added += 1
    if added:
        p["models"] = cat
    return added


def resolve_model(p, sel):
    """-> model id for an alias, a full id, or an unambiguous alias prefix; None when unknown"""
    cat = models(p)
    if sel in cat:
        return cat[sel]
    if sel in cat.values():
        return sel
    hits = [i for a, i in cat.items() if a.startswith(sel)]
    return hits[0] if len(set(hits)) == 1 else None


def selected_alias(p, model_id):
    return next((a for a, i in models(p).items() if i == model_id), model_id)


def env_models(env):
    """distinct model ids named in a Claude provider's env (roles + default + subagent), in order"""
    seen = []
    for var in MODEL_VARS.values():
        v = env.get(var)
        if v and v not in seen:
            seen.append(v)
    return seen


def models_url(p):
    base = (p["env"].get("ANTHROPIC_BASE_URL", "") if agent(p) == "claude" else p.get("base_url", "")).rstrip("/")
    if agent(p) == "claude":
        return base + ("/models" if base.endswith("/v1") else "/v1/models") + "?limit=1000"
    return base + "/models"


def fetch_models(p, timeout=15):
    """GET the endpoint's model list (Anthropic and OpenAI style both answer {"data": [{"id": ...}]})."""
    headers = {"User-Agent": "zorua"}
    if agent(p) == "claude":
        var = key_var(p["env"])
        headers["anthropic-version"] = "2023-06-01"
        headers["x-api-key" if var == "ANTHROPIC_API_KEY" else "Authorization"] = (
            p["env"][var] if var == "ANTHROPIC_API_KEY" else "Bearer " + p["env"].get(var, ""))
    else:
        headers["Authorization"] = "Bearer " + p.get("key", "")
    req = urllib.request.Request(models_url(p), headers=headers)
    try:
        data = json.load(urllib.request.urlopen(req, timeout=timeout))
    except urllib.error.HTTPError as e:
        raise RuntimeError("HTTP %d from %s" % (e.code, models_url(p).split("?")[0]))
    except Exception as e:
        raise RuntimeError("%s: %s" % (models_url(p).split("?")[0], getattr(e, "reason", e)))
    ids = [m.get("id") for m in (data.get("data") or []) if isinstance(m, dict)]
    return [i for i in ids if i]


def is_secret(var):
    u = var.upper()
    return any(m in u for m in SECRET_MARKS) and not u.endswith("_TOKENS")   # CLAUDE_CODE_MAX_OUTPUT_TOKENS is a number


def mask(value):
    return value[:3] + "…" + value[-4:] if len(value) > 12 else "***"


def shown(var, value):
    return mask(value) if is_secret(var) and value else value


def build_env(base_url, key, api_key=False, models=(), extra=()):
    """Assemble a provider env from `add` flags. models: ROLE=ID, extra: VAR=VALUE."""
    env = {"ANTHROPIC_BASE_URL": base_url.rstrip("/")}
    env["ANTHROPIC_API_KEY" if api_key else "ANTHROPIC_AUTH_TOKEN"] = key
    for spec in models:
        role, sep, mid = spec.partition("=")
        if not sep or role not in MODEL_VARS or not mid:
            raise ValueError("--model needs ROLE=ID with ROLE one of: %s" % ", ".join(MODEL_VARS))
        env[MODEL_VARS[role]] = mid
    for spec in extra:
        var, sep, val = spec.partition("=")
        if not sep or not re.match(r"^[A-Z_][A-Z0-9_]*$", var):
            raise ValueError("--env needs VAR=VALUE (VAR in capitals), got %r" % spec)
        env[var] = val
    return env


def host(env):
    return re.sub(r"^https?://", "", env.get("ANTHROPIC_BASE_URL", "")).split("/")[0] or "-"


def key_var(env):
    return next((v for v in ("ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY") if env.get(v)), "")


def _strip(var):
    return var.startswith(_STRIP_PREFIXES) or var in _STRIP_NAMES


def process_env(base, provider_env):
    """Environment for the launched claude: inherited overrides removed, provider env applied."""
    env = {k: v for k, v in base.items() if not _strip(k)}
    env.update(provider_env)
    return env


def user_settings_path(base):
    return os.path.join(base.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude"),
                        "settings.json")


def settings_for(base, provider_env):
    """The --settings document: the provider env, with every conflicting variable the
    user's own settings.json sets (and the provider does not) blanked out."""
    env = dict(provider_env)
    try:
        with open(user_settings_path(base)) as f:
            theirs = (json.load(f).get("env") or {})
    except (OSError, ValueError):
        theirs = {}
    for var in theirs:
        if _strip(var) and var not in env:
            env[var] = ""
    return {"env": env}


def write_settings(cfg, name, doc):
    path = os.path.join(cfg, "run", "%s.settings.json" % name)
    _write_private(path, json.dumps(doc, indent=2) + "\n")
    return path


# --------------------------------------------------------------------------
# Whole-provider documents (`provider get` / `provider put`, used by the web dashboard)
# --------------------------------------------------------------------------

ENV_VAR = re.compile(r"^[A-Z_][A-Z0-9_]*$")
ALIAS = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")
WIRE_APIS = ("responses", "chat")
_CONTROL = re.compile(r"[\x00-\x1f\x7f]")


def document(p, reveal=False):
    """-> the editable view of provider p; secrets are masked unless reveal"""
    if agent(p) == "claude":
        env = {var: val if reveal else shown(var, val) for var, val in p["env"].items()}
        return {"agent": "claude", "env": env, "models": models(p)}
    key = p.get("key", "")
    return {"agent": "codex", "base_url": p.get("base_url", ""), "key": key if reveal or not key else mask(key),
            "model": p.get("model", ""), "wire_api": p.get("wire_api", "responses"), "models": models(p)}


def _text(v, what, empty=False):
    if not isinstance(v, str) or _CONTROL.search(v) or (not v and not empty):
        raise ValueError("%s is missing or has control characters" % what)
    return v


def _base_url(v):
    _text(v, "base URL")
    m = re.match(r"^https?://([^/?#]*)", v)
    if not m or not m.group(1) or "@" in m.group(1):
        raise ValueError("base URL must be http(s):// with a host and no credentials")
    return v.rstrip("/")


def _keep(new, old, var=None):
    """A secret sent back in its masked form means 'unchanged'."""
    return old if old and new == (shown(var, old) if var else mask(old)) else new


def from_document(old, doc):
    """-> the provider dict for an edited document. Raises ValueError with a message that never
    contains a secret. The agent cannot change; a masked secret keeps its stored value."""
    if not isinstance(doc, dict) or doc.get("agent") != agent(old):
        raise ValueError("document must be an object for the same agent (%s)" % agent(old))
    cat = doc.get("models") or {}
    if not isinstance(cat, dict):
        raise ValueError("models must be an object {alias: model id}")
    for alias, mid in cat.items():
        if not ALIAS.match(alias):
            raise ValueError("model alias %r must use letters, digits, . _ - (max 64)" % alias[:40])
        _text(mid, "model id for %s" % alias)
    p = dict(old)
    if agent(old) == "claude":
        env = doc.get("env")
        if not isinstance(env, dict):
            raise ValueError("env must be an object {VAR: value}")
        new = {}
        for var, val in env.items():
            if not ENV_VAR.match(var):
                raise ValueError("%r is not an environment variable name (capitals, digits, _)" % var[:40])
            _text(val, var, empty=True)
            new[var] = _keep(val, old["env"].get(var, ""), var) if is_secret(var) else val
        new["ANTHROPIC_BASE_URL"] = _base_url(new.get("ANTHROPIC_BASE_URL"))
        if not key_var(new):
            raise ValueError("env needs ANTHROPIC_AUTH_TOKEN or ANTHROPIC_API_KEY")
        p["env"] = new
    else:
        p["base_url"] = _base_url(doc.get("base_url"))
        p["key"] = _keep(_text(doc.get("key"), "key"), old.get("key", ""))
        p["model"] = _text(doc.get("model"), "model")
        if doc.get("wire_api") not in WIRE_APIS:
            raise ValueError("wire_api must be one of: %s" % ", ".join(WIRE_APIS))
        p["wire_api"] = doc["wire_api"]
    if cat:
        p["models"] = dict(cat)
    else:
        p.pop("models", None)
    return p


def backup(cfg):
    """Keep the previous providers.json next to it (0600) before a rewrite."""
    try:
        with open(_file(cfg)) as f:
            _write_private(_file(cfg) + ".bak", f.read())
    except FileNotFoundError:
        pass


# --------------------------------------------------------------------------
# Codex
# --------------------------------------------------------------------------

def _toml_str(v):
    return json.dumps(v)          # JSON string escapes are valid TOML basic-string escapes


def build_codex(base_url, key, model, wire_api="responses"):
    if not model:
        raise ValueError("a Codex provider needs --model ID (Codex would otherwise send its own default model)")
    return {"kind": "codex", "base_url": base_url.rstrip("/"), "key": key, "model": model, "wire_api": wire_api}


def codex_args(name, p, model=None):
    """-c overrides that make codex use provider `p` (the table key is the provider name)."""
    table = "zorua_%s" % name.replace("-", "_")
    inline = "{name=%s, base_url=%s, wire_api=%s, env_key=%s}" % (
        _toml_str(name), _toml_str(p["base_url"]), _toml_str(p.get("wire_api", "responses")), _toml_str(CODEX_KEY_VAR))
    return ["-c", "model_provider=%s" % _toml_str(table),
            "-c", "model_providers.%s=%s" % (table, inline),
            "-c", "model=%s" % _toml_str(model or p["model"])]


def codex_env(base, p):
    env = dict(base)
    env[CODEX_KEY_VAR] = p.get("key", "")
    return env


# --------------------------------------------------------------------------
# Import from cc-switch (read-only)
# --------------------------------------------------------------------------

def sanitize_name(raw):
    n = re.sub(r"[^A-Za-z0-9_-]+", "-", raw.strip()).strip("-").lower()
    return n or "provider"


def parse_codex_config(text):
    """-> (model, base_url, wire_api) from a cc-switch Codex config.toml string, or None.

    Reads the one [model_providers.<id>] table that `model_provider` selects; this is a small
    purpose-built reader (no tomllib before Python 3.11), not a TOML parser."""
    head = text.split("\n[", 1)[0]
    m = re.search(r'^\s*model_provider\s*=\s*"([^"]+)"', head, re.M)
    if not m:
        return None
    model = re.search(r'^\s*model\s*=\s*"([^"]+)"', head, re.M)
    sec = re.search(r"^\[model_providers\.%s\]\s*\n(.*?)(?=^\[|\Z)" % re.escape(m.group(1)), text, re.M | re.S)
    if not sec or not model:
        return None
    url = re.search(r'^\s*base_url\s*=\s*"([^"]+)"', sec.group(1), re.M)
    wire = re.search(r'^\s*wire_api\s*=\s*"([^"]+)"', sec.group(1), re.M)
    if not url:
        return None
    return model.group(1), url.group(1), (wire.group(1) if wire else "responses")


def cc_switch_codex_providers(db):
    """-> [(display name, provider)] for cc-switch's custom Codex providers that carry their own
    base URL, model and API key (official logins are skipped)."""
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    try:
        rows = con.execute("SELECT name, settings_config FROM providers WHERE app_type='codex' "
                           "ORDER BY sort_index, name").fetchall()
    finally:
        con.close()
    out = []
    for name, cfg in rows:
        try:
            c = json.loads(cfg)
            key = (c.get("auth") or {}).get("OPENAI_API_KEY") or ""
            parsed = parse_codex_config(c.get("config") or "")
        except (ValueError, AttributeError):
            continue
        if not key or not parsed:
            continue
        prov = build_codex(parsed[1], key, parsed[0], parsed[2])
        try:
            listed = [m.get("model") for m in ((c.get("modelCatalog") or {}).get("models") or [])]
        except AttributeError:
            listed = []
        add_models(prov, [parsed[0]] + listed)
        out.append((name, prov))
    return out


def cc_switch_providers(db):
    """-> [(display name, env)] for cc-switch's custom Claude providers that carry their own
    endpoint and key (official logins, proxy-managed entries and other apps are skipped)."""
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    out = []
    try:
        rows = con.execute("SELECT name, settings_config FROM providers WHERE app_type='claude' "
                           "ORDER BY sort_index, name").fetchall()
    finally:
        con.close()
    for name, cfg in rows:
        try:
            env = {k: str(v) for k, v in (json.loads(cfg).get("env") or {}).items()}
        except ValueError:
            continue
        url = env.get("ANTHROPIC_BASE_URL", "")
        key = env.get("ANTHROPIC_AUTH_TOKEN") or env.get("ANTHROPIC_API_KEY") or ""
        if not url or not key or key == "PROXY_MANAGED" or re.match(r"https?://(127\.0\.0\.1|localhost)", url):
            continue
        out.append((name, env))
    return out
