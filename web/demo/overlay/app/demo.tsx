"use client";

import type { Account, Binding, Check, LoginJob, Provider, ProviderDoc, ZoruaState } from "@/lib/types";

/*
 * The backend of the static demo. The dashboard calls /api/state, /api/check, /api/provider, /api/action
 * and /api/login; here `window.fetch` answers those from an in-memory copy of some made-up accounts, so the
 * real dashboard code runs unchanged. Nothing is sent anywhere and a reload starts over.
 */

const win = (window_seconds: number, used_percent: number, reset_after_seconds: number) => ({ window_seconds, used_percent, reset_after_seconds });
const blank = { windows: [], error: null, age_seconds: null, relay: null, shadowed_by: null };

const db = {
  accounts: [
    { name: "default", agent: "codex", home: "/Users/demo/.codex", state: "ok", email: "demo@example.com", plan: "pro", until: null, usage: { ...blank, windows: [win(18000, 34, 6120), win(604800, 61, 251000)], age_seconds: 240 } },
    { name: "work", agent: "codex", home: "/Users/demo/.codex-work", state: "ok", email: "work@example.com", plan: "team", until: null, usage: { ...blank, windows: [win(18000, 92, 1400), win(604800, 48, 320000)], age_seconds: 90 } },
    { name: "side", agent: "codex", home: "/Users/demo/.codex-side", state: "none", email: null, plan: null, until: null, usage: { ...blank } },
    { name: "main", agent: "claude", home: "/Users/demo/.claude", state: "ok", email: "me@example.com", plan: "max", until: null, usage: { ...blank, windows: [win(18000, 57, 9000), win(604800, 22, 400000)], age_seconds: 600, relay: true } },
    { name: "lab", agent: "claude", home: "/Users/demo/.claude-lab", state: "ok", email: "lab@example.com", plan: "pro", until: null, usage: { ...blank, relay: false } },
  ] as Account[],
  providers: [
    { name: "kimi", agent: "claude", endpoint: "https://api.moonshot.cn/anthropic", models: { k2: "kimi-k2", "k2-thinking": "kimi-k2-thinking" } },
    { name: "glm", agent: "claude", endpoint: "https://open.bigmodel.cn/api/anthropic", models: { glm: "glm-4.6" } },
    { name: "relay", agent: "codex", endpoint: "https://relay.example.com/v1", models: {} },
  ] as Provider[],
  bindings: [
    { name: "work", dir: "/Users/demo/code/api", kind: "codex" },
    { name: "kimi", dir: "/Users/demo/code/scratch", kind: "provider" },
  ] as Binding[],
  // Full documents with the real (made-up) keys; they are masked when read unless "show keys" is pressed.
  docs: {
    kimi: { agent: "claude", env: { ANTHROPIC_BASE_URL: "https://api.moonshot.cn/anthropic", ANTHROPIC_AUTH_TOKEN: "sk-demo-kimi-0000000000000000k2xy", ANTHROPIC_MODEL: "kimi-k2", ANTHROPIC_DEFAULT_SONNET_MODEL: "kimi-k2", API_TIMEOUT_MS: "600000" }, models: { k2: "kimi-k2", "k2-thinking": "kimi-k2-thinking" } },
    glm: { agent: "claude", env: { ANTHROPIC_BASE_URL: "https://open.bigmodel.cn/api/anthropic", ANTHROPIC_AUTH_TOKEN: "sk-demo-glm-00000000000000009f3a", ANTHROPIC_MODEL: "glm-4.6" }, models: { glm: "glm-4.6" } },
    relay: { agent: "codex", base_url: "https://relay.example.com/v1", key: "sk-demo-relay-000000000000000a1b2", model: "gpt-6.1-sol", wire_api: "responses", models: {} },
  } as Record<string, ProviderDoc>,
  checks: {} as Record<string, Check>,
  jobs: {} as Record<string, LoginJob>,
};

const NAME = /^[A-Za-z0-9_-]{1,32}$/;
class Bad extends Error {}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v));
const mask = (v: string) => (v.length > 8 ? `sk-…${v.slice(-4)}` : "…");
const isSecret = (k: string) => /TOKEN|KEY|SECRET|PASSWORD/.test(k.toUpperCase()) && !k.toUpperCase().endsWith("_TOKENS");

function state(): ZoruaState {
  return { version: "0.7.0", generated_at: Math.floor(Date.now() / 1000), accounts: clone(db.accounts), providers: clone(db.providers), bindings: clone(db.bindings) };
}

function name(v: unknown): string {
  if (typeof v !== "string" || !NAME.test(v)) throw new Bad("name may only use letters, digits, '-' and '_' (up to 32)");
  return v;
}

function startLogin(n: string): LoginJob {
  const job: LoginJob = { name: n, status: "running", output: "Opening your browser to sign in…\n", urls: ["https://example.com/oauth/authorize?demo=1"], startedAt: Date.now() };
  db.jobs[n] = job;
  return clone(job);
}

function readJob(n: string): LoginJob | null {
  const job = db.jobs[n];
  if (!job) return null;
  if (job.status === "running" && Date.now() - job.startedAt > 3000) {
    job.status = "done";
    job.output += "Signed in.\n";
    const a = db.accounts.find((x) => x.name === n);
    if (a && a.state === "none") Object.assign(a, { state: "ok", email: `${n}@example.com`, plan: "pro", usage: { ...blank, windows: [win(18000, 6, 17000), win(604800, 12, 500000)], age_seconds: 5, relay: a.agent === "claude" ? true : null } });
  }
  return clone(job);
}

function doc(n: string, reveal: boolean): ProviderDoc {
  const d = clone(db.docs[n]);
  if (reveal) return d;
  if (d.agent === "claude") {
    for (const k of Object.keys(d.env)) if (isSecret(k)) d.env[k] = mask(d.env[k]);
  } else {
    d.key = mask(d.key);
  }
  return d;
}

function checkOf(n: string): Check {
  const bad = n === "glm";
  const c: Check = bad
    ? { status: "fail", http: 401, ms: 90, via: "GET /models", detail: "key rejected (HTTP 401)", checked_at: Math.floor(Date.now() / 1000) }
    : { status: "ok", http: 200, ms: 180 + Math.floor(Math.random() * 160), via: "GET /models", detail: "reachable, key accepted", checked_at: Math.floor(Date.now() / 1000) };
  db.checks[n] = c;
  return c;
}

function perform(b: Record<string, unknown>): { ok: true; message: string; job?: LoginJob } {
  switch (b.action) {
    case "account.add": {
      const n = name(b.name);
      if (db.accounts.some((a) => a.name === n)) throw new Bad(`account '${n}' already exists`);
      const agent = b.agent === "claude" ? "claude" : "codex";
      db.accounts.push({ name: n, agent, home: `/Users/demo/.${agent}-${n}`, state: "none", email: null, plan: null, until: null, usage: { ...blank } });
      if (b.login === true) return { ok: true, message: `added ${n}; sign-in started`, job: startLogin(n) };
      return { ok: true, message: `added ${n}; run sign-in when you are ready` };
    }
    case "account.login": {
      const n = name(b.name);
      if (!db.accounts.some((a) => a.name === n)) throw new Bad(`unknown account '${n}'`);
      return { ok: true, message: `sign-in started for ${n}`, job: startLogin(n) };
    }
    case "account.login.cancel": {
      const n = name(b.name);
      const had = db.jobs[n]?.status === "running";
      if (had) db.jobs[n].status = "failed";
      return { ok: true, message: had ? "sign-in cancelled" : "no sign-in is running" };
    }
    case "account.remove": {
      const n = name(b.name);
      if (n === "default") throw new Bad("default is built-in and cannot be removed");
      const a = db.accounts.find((x) => x.name === n);
      if (!a) throw new Bad(`unknown account '${n}'`);
      if (b.purge === true && b.confirm !== n) throw new Bad("type the account name to confirm deleting its data");
      db.accounts = db.accounts.filter((x) => x.name !== n);
      db.bindings = db.bindings.filter((x) => x.name !== n);
      return { ok: true, message: b.purge === true ? `removed ${n} and deleted its data` : `removed ${n}; data kept in ${a.home}` };
    }
    case "provider.add": {
      const n = name(b.name);
      if (db.providers.some((p) => p.name === n)) throw new Bad(`provider '${n}' already exists`);
      const agent = b.agent === "codex" ? "codex" : "claude";
      const url = String(b.baseUrl ?? "");
      try {
        new URL(url);
      } catch {
        throw new Bad("base URL is not a valid URL");
      }
      const model = typeof b.model === "string" && b.model ? b.model : "";
      if (agent === "codex" && !model) throw new Bad("a Codex provider needs a model");
      db.providers.push({ name: n, agent, endpoint: url, models: model ? { default: model } : {} });
      db.docs[n] = agent === "codex" ? { agent, base_url: url, key: String(b.key ?? ""), model, wire_api: "responses", models: {} } : { agent, env: { ANTHROPIC_BASE_URL: url, ANTHROPIC_AUTH_TOKEN: String(b.key ?? ""), ...(model ? { ANTHROPIC_MODEL: model } : {}) }, models: model ? { default: model } : {} };
      return { ok: true, message: `added provider ${n}` };
    }
    case "provider.save": {
      const n = name(b.name);
      const p = db.providers.find((x) => x.name === n);
      if (!p || typeof b.doc !== "object" || b.doc === null) throw new Bad(`unknown provider '${n}'`);
      const cur = db.docs[n];
      const next = clone(b.doc as ProviderDoc);
      // A secret that still shows its masked form keeps the stored value.
      if (next.agent === "claude" && cur.agent === "claude") for (const k of Object.keys(next.env)) if (isSecret(k) && next.env[k] === mask(cur.env[k] ?? "")) next.env[k] = cur.env[k];
      if (next.agent === "codex" && cur.agent === "codex" && next.key === mask(cur.key)) next.key = cur.key;
      db.docs[n] = next;
      p.endpoint = next.agent === "claude" ? (next.env.ANTHROPIC_BASE_URL ?? p.endpoint) : next.base_url;
      p.models = next.models;
      delete db.checks[n];
      return { ok: true, message: `saved provider ${n}` };
    }
    case "provider.remove": {
      const n = name(b.name);
      if (!db.providers.some((p) => p.name === n)) throw new Bad(`unknown provider '${n}'`);
      db.providers = db.providers.filter((p) => p.name !== n);
      db.bindings = db.bindings.filter((x) => x.name !== n);
      delete db.docs[n];
      delete db.checks[n];
      return { ok: true, message: `removed provider ${n}` };
    }
    case "binding.add": {
      const n = name(b.name);
      const dir = String(b.dir ?? "");
      if (!dir.startsWith("/")) throw new Bad("directory must be an absolute path");
      const acc = db.accounts.find((a) => a.name === n);
      if (!acc && !db.providers.some((p) => p.name === n)) throw new Bad(`unknown account or provider '${n}'`);
      db.bindings = [...db.bindings.filter((x) => x.dir !== dir), { name: n, dir, kind: acc ? acc.agent : "provider" }];
      return { ok: true, message: `bound ${dir} to ${n}` };
    }
    case "binding.remove": {
      const dir = String(b.dir ?? "");
      if (!db.bindings.some((x) => x.dir === dir)) throw new Bad("no such binding");
      db.bindings = db.bindings.filter((x) => x.dir !== dir);
      return { ok: true, message: `unbound ${dir}` };
    }
    default:
      throw new Bad("unknown action");
  }
}

async function handle(path: string, query: URLSearchParams, body: Record<string, unknown>): Promise<unknown> {
  await sleep(120 + Math.random() * 200);
  if (path === "/api/state") return { data: state(), stale: false, error: null, checks: clone(db.checks) };
  if (path === "/api/login") return { job: readJob(query.get("name") ?? "") };
  if (path === "/api/check") {
    const n = name(body.name);
    if (!db.providers.some((p) => p.name === n)) throw new Bad(`unknown provider '${n}'`);
    await sleep(500 + Math.random() * 500);
    return { check: checkOf(n) };
  }
  if (path === "/api/provider") {
    const n = name(body.name);
    if (!db.docs[n]) throw new Bad(`unknown provider '${n}'`);
    return { doc: doc(n, body.reveal === true) };
  }
  if (path === "/api/action") return perform(body);
  return undefined;
}

if (typeof window !== "undefined" && !(window as unknown as { __zoruaDemo?: boolean }).__zoruaDemo) {
  (window as unknown as { __zoruaDemo?: boolean }).__zoruaDemo = true;
  const real = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url, location.href);
    if (url.origin !== location.origin || !url.pathname.startsWith("/api/")) return real(input, init);
    const json = (status: number, v: unknown) => new Response(JSON.stringify(v), { status, headers: { "Content-Type": "application/json" } });
    try {
      const body = typeof init?.body === "string" ? (JSON.parse(init.body) as Record<string, unknown>) : {};
      const out = await handle(url.pathname, url.searchParams, body);
      return out === undefined ? json(404, { error: "not found" }) : json(200, out);
    } catch (e) {
      return json(e instanceof Bad ? 400 : 500, { error: e instanceof Error ? e.message : String(e) });
    }
  };
}

/** A small badge so nobody mistakes this for their own accounts. */
export function Demo() {
  return (
    <a
      href="https://github.com/szupzj18/zorua"
      target="_blank"
      rel="noreferrer"
      className="squircle fixed bottom-3 left-3 z-40 hidden max-w-[calc(100vw-1.5rem)] items-center gap-2 rounded-xl border border-line-strong bg-panel/90 px-3 py-1.5 text-[11px] text-dim shadow-pop backdrop-blur hover:text-fg sm:flex"
    >
      <span className="size-1.5 rounded-full bg-accent" aria-hidden />
      Live demo · made-up data · changes stay in this tab
    </a>
  );
}
