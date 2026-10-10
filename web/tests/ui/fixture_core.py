#!/usr/bin/env python3
"""A stateful stand-in for zorua_core.py, used by tests/ui/run.mjs.

It keeps its state in $FX_DIR/state.json and logs every call to $FX_DIR/calls.log. Flag files in $FX_DIR switch
behaviour: `slow` makes `usage` take 1.5 s, `die-early` makes `provider put` exit without reading stdin.
"""
import json, os, sys, time

D = os.environ["FX_DIR"]                      # state + logs live here
ST = os.path.join(D, "state.json")
def win(sec, pct, reset): return {"window_seconds": sec, "used_percent": pct, "reset_after_seconds": reset}
def blank(): return {"windows": [], "error": None, "age_seconds": None, "relay": None, "shadowed_by": None}
DEFAULT = {
  "accounts": [
    {"name": "default", "agent": "codex", "home": "/Users/demo/.codex", "state": "ok", "email": "demo@example.com", "plan": "pro", "until": None, "usage": {**blank(), "windows": [win(18000, 34, 6120), win(604800, 61, 251000)], "age_seconds": 240}},
    {"name": "work", "agent": "codex", "home": "/Users/demo/.codex-work", "state": "ok", "email": "work@example.com", "plan": "team", "until": None, "usage": {**blank(), "windows": [win(18000, 92, 1400), win(604800, 48, 320000)], "age_seconds": 90}},
  ],
  "providers": [
    {"name": "kimi", "agent": "claude", "endpoint": "https://api.moonshot.cn/anthropic", "models": {"k2": "kimi-k2"}},
    {"name": "glm", "agent": "claude", "endpoint": "https://open.bigmodel.cn/api/anthropic", "models": {}},
  ],
  "bindings": [{"name": "work", "dir": os.environ.get("FX_BIND1", "/tmp"), "kind": "codex"}, {"name": "kimi", "dir": os.environ.get("FX_BIND2", "/var"), "kind": "provider"}],
}
def load():
    if os.path.exists(ST): return json.load(open(ST))
    return DEFAULT
def save(s): json.dump(s, open(ST, "w"))
def log(*a):
    with open(os.path.join(D, "calls.log"), "a") as f: f.write(" ".join(map(str, a)) + "\n")
a = sys.argv[1:]
log(*a)
s = load()
def out(): print(json.dumps({"version": "0.7.0", "generated_at": int(time.time()), **s}))
if a[:1] == ["usage"]:
    if os.path.exists(os.path.join(D, "slow")): time.sleep(1.5)
    out()
elif a[:1] == ["ls"]: out()
elif a[:1] == ["unbind"]:
    s["bindings"] = [b for b in s["bindings"] if b["dir"] != a[1]]; save(s)
elif a[:1] == ["bind"]:
    s["bindings"] = [b for b in s["bindings"] if b["dir"] != os.getcwd()] + [{"name": a[1], "dir": os.getcwd(), "kind": "provider"}]; save(s)
elif a[:2] == ["provider", "put"]:
    data = ""
    if os.path.exists(os.path.join(D, "die-early")): sys.stderr.write("providers.json is not valid JSON\n"); sys.exit(2)   # exits without reading stdin
    data = sys.stdin.read()
elif a[:2] == ["provider", "get"]:
    print(json.dumps({"agent": "claude", "env": {"ANTHROPIC_BASE_URL": "https://api.moonshot.cn/anthropic", "ANTHROPIC_AUTH_TOKEN": "sk-…wxyz", "ANTHROPIC_MODEL": "kimi-k2"}, "models": {"k2": "kimi-k2"}}))
elif a[:2] == ["provider", "check"]:
    print(json.dumps({"status": "fail" if a[2] == "glm" else "ok", "http": 401 if a[2] == "glm" else 200, "ms": 100, "via": "GET /models", "detail": "key rejected (HTTP 401)" if a[2] == "glm" else "reachable, key accepted", "checked_at": int(time.time())}))
elif a[:1] == ["login"]:
    print("Open https://example.com/oauth/authorize?fake=1 to sign in", flush=True); time.sleep(2.5)
else: pass
