"""API checks for the Zorua web dashboard. Run through tests/run.sh (isolated HOME, fake CLIs)."""
import json, time, urllib.request, urllib.error, os, sys
ROOT = os.environ["ZW_ROOT"]
B = os.environ["ZW_BASE"]
H = {"Content-Type": "application/json", "Origin": B, "X-Zorua-Web": "1"}
def post(body, headers=None, host=None):
    h = dict(H if headers is None else headers)
    if host: h["Host"] = host
    r = urllib.request.Request(B + "/api/action", data=json.dumps(body).encode(), headers=h, method="POST")
    try:
        with urllib.request.urlopen(r, timeout=60) as f: return f.status, json.load(f)
    except urllib.error.HTTPError as e: return e.code, json.load(e)
def get(path):
    with urllib.request.urlopen(B + path, timeout=60) as f: return json.load(f)
def check(label, cond, extra=""):
    print(("PASS " if cond else "FAIL ") + label, extra if not cond else ""); 
    if not cond: sys.exit(1)

# --- guards
check("no Origin -> 403", post({"action":"x"}, headers={"Content-Type":"application/json","X-Zorua-Web":"1"})[0] == 403)
check("foreign Origin -> 403", post({"action":"x"}, headers={**H,"Origin":"http://evil.example"})[0] == 403)
check("no custom header -> 403", post({"action":"x"}, headers={"Content-Type":"application/json","Origin":B})[0] == 403)
check("text/plain -> 415", post({"action":"x"}, headers={"Content-Type":"text/plain","Origin":B,"X-Zorua-Web":"1"})[0] == 415)
check("bad Host -> 403", post({"action":"x"}, host="evil.example")[0] == 403)
check("unknown action -> 400", post({"action":"nope"})[0] == 400)

# --- accounts
s, r = post({"action":"account.add","name":"w1","agent":"codex","login":False}); check("add codex", s == 200, r)
s, r = post({"action":"account.add","name":"c1","agent":"claude","login":True}); check("add claude + login job", s == 200 and r.get("job",{}).get("status") == "running", r)
check("dup name rejected", post({"action":"account.add","name":"w1","agent":"codex","login":False})[0] == 422)
check("bad name rejected", post({"action":"account.add","name":"a b;rm","agent":"codex"})[0] == 400)
time.sleep(1)
j = get("/api/login?name=c1")["job"]; check("login job captured URL", j and any("claude.ai" in u for u in j["urls"]), j)
time.sleep(4)
j = get("/api/login?name=c1")["job"]; check("login job finished", j["status"] == "done", j)
st = get("/api/state?refresh=1")["data"]
acc = {a["name"]: a for a in st["accounts"]}
check("state lists new accounts", "w1" in acc and acc["c1"]["state"] == "ok" and acc["c1"]["email"] == "fake@example.com", acc.get("c1"))
s, r = post({"action":"account.login","name":"w1"}); check("codex login job starts", s == 200 and r["job"]["status"] == "running", r)
time.sleep(3); j = get("/api/login?name=w1")["job"]; check("codex login failed cleanly", j["status"] == "failed", j)
check("login unknown account 400", post({"action":"account.login","name":"zzz"})[0] == 400)

# --- providers (key must never come back)
KEY = "sk-test-SECRET-1234567890"
s, r = post({"action":"provider.add","agent":"claude","name":"kimi2","baseUrl":"https://api.moonshot.cn/anthropic","key":KEY,"model":"kimi-k2"}); check("add claude provider", s == 200, r)
s, r = post({"action":"provider.add","agent":"codex","name":"ds2","baseUrl":"http://127.0.0.1:8080/v1","key":KEY,"model":"gpt-6.1-sol"}); check("add codex provider", s == 200, r)
check("codex provider needs model", post({"action":"provider.add","agent":"codex","name":"ds3","baseUrl":"https://x.example","key":KEY})[0] == 400)
check("bad scheme rejected", post({"action":"provider.add","agent":"claude","name":"p9","baseUrl":"file:///etc/passwd","key":KEY})[0] == 400)
check("credentials in URL rejected", post({"action":"provider.add","agent":"claude","name":"p9","baseUrl":"https://u:p@x.example","key":KEY})[0] == 400)
s, r = post({"action":"provider.add","agent":"claude","name":"kimi2","baseUrl":"https://x.example","key":KEY}); check("dup provider -> 422, key not echoed", s == 422 and KEY not in json.dumps(r), r)
raw = json.dumps(get("/api/state?refresh=1"))
check("state lists providers, no key", "kimi2" in raw and "ds2" in raw and KEY not in raw)
cfg = open(ROOT + "/cfg/providers.json").read(); check("key stored by zorua (0600)", KEY in cfg and oct(os.stat(ROOT + "/cfg/providers.json").st_mode & 0o777) == "0o600")
check("provider.remove unknown 400", post({"action":"provider.remove","name":"w1"})[0] == 400)
s, r = post({"action":"provider.remove","name":"ds2"}); check("remove provider", s == 200, r)

# --- bindings
d = ROOT + "/proj"; os.makedirs(d, exist_ok=True)
s, r = post({"action":"binding.add","dir":d,"name":"w1"}); check("bind dir", s == 200, r)
bs = get("/api/state?refresh=1")["data"]["bindings"]; check("binding listed", any(b["dir"] == d and b["name"] == "w1" for b in bs), bs)
check("bind relative path 400", post({"action":"binding.add","dir":"rel/path","name":"w1"})[0] == 400)
check("bind missing dir 400", post({"action":"binding.add","dir":"/nonexistent/zz","name":"w1"})[0] == 400)
check("bind unknown target 400", post({"action":"binding.add","dir":d,"name":"nobody"})[0] == 400)
s, r = post({"action":"binding.remove","dir":d}); check("unbind", s == 200, r)
check("unbind again 400", post({"action":"binding.remove","dir":d})[0] == 400)

# --- remove accounts
check("remove default refused", post({"action":"account.remove","name":"default"})[0] == 400)
check("purge needs typed confirm", post({"action":"account.remove","name":"w1","purge":True})[0] == 400)
home = ROOT + "/home"
check("w1 dir exists", os.path.isdir(home + "/.codex-w1"))
s, r = post({"action":"account.remove","name":"w1"}); check("remove keeps data", s == 200 and os.path.isdir(home + "/.codex-w1"), r)
s, r = post({"action":"account.remove","name":"c1","purge":True,"confirm":"c1"}); check("purge deletes data", s == 200 and not os.path.exists(home + "/.claude-c1"), r)
print("ALL OK")
