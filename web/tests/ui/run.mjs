// Browser tests for the dashboard: start the built server against a fake core (fixture_core.py) and drive it
// with Chrome. Needs `npm run build` first and a Chrome (CHROME_PATH, or a common install location).
// Never touches your real accounts. Run: npm run test:ui
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";

const WEB = fileURLToPath(new URL("../..", import.meta.url));
const PORT = process.env.ZW_UI_PORT ?? "4949";
const BASE = `http://127.0.0.1:${PORT}`;
const CHROME = [
  process.env.CHROME_PATH,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/google-chrome-stable",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
].find((p) => p && fs.existsSync(p));
if (!CHROME) {
  console.log("no Chrome found (set CHROME_PATH): UI tests skipped");
  process.exit(process.env.CI ? 1 : 0);
}

const ROOT = fs.mkdtempSync(path.join(os.tmpdir(), "zorua-ui-"));
const FX = path.join(ROOT, "fx");
for (const d of [FX, path.join(ROOT, "bind1"), path.join(ROOT, "bind2")]) fs.mkdirSync(d);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const logFd = fs.openSync(path.join(FX, "server.log"), "w");
const server = spawn("node", ["node_modules/next/dist/bin/next", "start", ".", "-H", "127.0.0.1", "-p", PORT], {
  cwd: WEB,
  env: { ...process.env, ZORUA_CORE: path.join(WEB, "tests/ui/fixture_core.py"), FX_DIR: FX, FX_BIND1: path.join(ROOT, "bind1"), FX_BIND2: path.join(ROOT, "bind2") },
  stdio: ["ignore", logFd, logFd],
});

/** Poll until `fn` returns something truthy, or give up after `ms`. */
async function until(fn, ms = 8000, step = 100) {
  const end = Date.now() + ms;
  for (;;) {
    const v = await Promise.resolve(fn()).catch(() => false);
    if (v) return v;
    if (Date.now() > end) return false;
    await sleep(step);
  }
}

for (let i = 0; i < 80 && !(await fetch(BASE).then((r) => r.ok).catch(() => false)); i++) await sleep(250);

const results = [];
const ok = (name, pass, note = "") => results.push({ name, pass, note });
const W = { "content-type": "application/json", "x-zorua-web": "1", origin: BASE };
const post = (p, body) => fetch(BASE + p, { method: "POST", headers: W, body: JSON.stringify(body) }).then(async (r) => ({ status: r.status, body: await r.json().catch(() => null) }));
const browser = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox"] });
const open = async () => {
  const p = await browser.newPage();
  await p.setViewport({ width: 1280, height: 900 });
  return p;
};
const text = (p) => p.evaluate(() => document.body.textContent);
const has = (p, re) => async () => re.test(await text(p));
const baseState = await fetch(BASE + "/api/state").then((r) => r.json());
const clone = (v) => JSON.parse(JSON.stringify(v));
const setField = (p, i, v) =>
  p.evaluate(
    (i, v) => {
      const t = document.querySelectorAll("textarea")[i];
      Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set.call(t, v);
      t.dispatchEvent(new Event("input", { bubbles: true }));
      t.focus();
    },
    i,
    v,
  );
const navButton = (p, label) => p.evaluateHandle((l) => [...document.querySelectorAll("nav button")].find((x) => x.textContent.trim() === l), label);
const signIn = (p, email) =>
  p.evaluate((email) => {
    const li = [...document.querySelectorAll("li")].find((l) => l.textContent.includes(email));
    [...li.querySelectorAll("button")].find((x) => x.textContent.trim() === "sign in").click();
  }, email);
const palette = async (p, q) => {
  await p.keyboard.press("/");
  await sleep(250);
  await p.keyboard.type(q);
  await sleep(150);
  await p.keyboard.press("Enter");
};

try {
  // The toast: closing one with the pointer over it must not stop later ones from timing out.
  {
    const p = await open();
    await p.goto(BASE, { waitUntil: "networkidle0" });
    await palette(p, "zorua use work");
    const dismiss = await until(() => p.$('button[aria-label="Dismiss"]'));
    await dismiss.hover();
    await dismiss.click();
    await p.mouse.move(5, 5);
    await sleep(300);
    await palette(p, "zorua use work");
    await until(has(p, /Copied:/), 3000);
    ok("a toast times out after an earlier one was closed with the pointer over it", await until(async () => !/Copied:/.test(await text(p)), 12000));
    await p.close();
  }

  // Leaving a provider page right after editing a field: the save is already on its way.
  {
    const p = await open();
    let prompt = null;
    p.on("dialog", async (d) => {
      prompt = d.message();
      await d.dismiss();
    });
    await p.goto(BASE + "/#/provider/kimi", { waitUntil: "networkidle0" });
    await until(() => p.$("textarea"));
    await setField(p, 0, "https://api.example.com/x");
    await sleep(100);
    await (await navButton(p, "Overview")).asElement().click();
    await sleep(1200);
    ok("leaving right after editing a provider field does not ask to discard", prompt === null && (await p.evaluate(() => location.hash)) === "#/", prompt ?? "");
    await p.close();
  }
  {
    const p = await open();
    let prompt = null;
    p.on("dialog", async (d) => {
      prompt = d.message();
      await d.dismiss();
    });
    await p.goto(BASE + "/#/provider/kimi", { waitUntil: "networkidle0" });
    await until(() => p.$("textarea"));
    await setField(p, 0, "https://api.example.com/y");
    await p.evaluate(() => document.activeElement.blur());
    await setField(p, 1, "sk-newer-key-0000");
    await (await navButton(p, "Overview")).asElement().click();
    await sleep(300);
    ok("an edit newer than the save in flight still asks before leaving", prompt !== null);
    await p.close();
  }

  // Signing in twice: the banner follows the second run.
  {
    const p = await open();
    await p.goto(BASE + "/#/", { waitUntil: "networkidle0" });
    await until(has(p, /demo@example\.com/));
    await signIn(p, "demo@example.com");
    const first = await until(has(p, /sign-in default: done/), 12000);
    await signIn(p, "demo@example.com");
    const second = await until(has(p, /waiting for the browser/), 3000);
    ok("a second sign-in of the same account shows the new run", first && second && !/sign-in default: done/.test(await text(p)));
    await p.close();
  }
  // A failed poll must not end the wait for a sign-in.
  {
    const p = await open();
    await p.goto(BASE + "/#/", { waitUntil: "networkidle0" });
    await until(has(p, /work@example\.com/));
    await p.setRequestInterception(true);
    let polls = 0;
    p.on("request", (r) => (r.url().includes("/api/login") && ++polls <= 2 ? r.abort() : r.continue()));
    await signIn(p, "work@example.com");
    ok("the sign-in banner survives two failed polls and reports the result", await until(has(p, /sign-in work: done/), 20000, 250));
    await p.close();
  }

  // Responses can arrive out of order.
  {
    const p = await open();
    await p.goto(BASE, { waitUntil: "networkidle0" });
    await p.setRequestInterception(true);
    let n = 0;
    p.on("request", async (r) => {
      if (!r.url().includes("/api/state")) return r.continue();
      const body = clone(baseState);
      if (++n === 1) {
        body.data.accounts = body.data.accounts.filter((a) => a.name === "default");
        await sleep(2500);
      } else {
        body.data.accounts.push({ ...body.data.accounts[0], name: "fresh", email: "fresh@example.com" });
      }
      r.respond({ status: 200, contentType: "application/json", body: JSON.stringify(body) }).catch(() => {});
    });
    await p.keyboard.press("r");
    await sleep(150);
    await p.keyboard.press("r");
    await until(has(p, /fresh@example\.com/), 5000);
    await sleep(3000);
    ok("a slow older response does not overwrite a newer one", /fresh@example\.com/.test(await text(p)));
    await p.close();
  }
  // A removed provider's last check must not come back with a new provider of the same name.
  {
    const p = await open();
    await p.setRequestInterception(true);
    let n = 0;
    const failing = { status: "fail", http: 401, ms: 90, via: "GET /models", detail: "key rejected (HTTP 401)", checked_at: Math.floor(Date.now() / 1000) };
    p.on("request", (r) => {
      if (!r.url().includes("/api/state")) return r.continue();
      const i = ++n;
      const body = clone(baseState);
      body.checks = i === 1 ? { glm: failing } : {};
      if (i === 2) body.data.providers = body.data.providers.filter((x) => x.name !== "glm");
      r.respond({ status: 200, contentType: "application/json", body: JSON.stringify(body) }).catch(() => {});
    });
    await p.goto(BASE, { waitUntil: "networkidle0" });
    const shown = await until(has(p, /key rejected/));
    await sleep(5500); // the forced refresh is limited to one per 5 s on the server, not here; this only spaces the keys
    await p.keyboard.press("r");
    await sleep(500);
    await p.keyboard.press("r");
    await sleep(800);
    ok("a removed provider's failed check is forgotten when a provider of that name returns", shown && !/key rejected/.test(await text(p)), shown ? "" : "setup: the failure was never shown");
    await p.close();
  }

  // Server side.
  {
    const calls = () => (fs.readFileSync(path.join(FX, "calls.log"), "utf8").match(/^ls /gm) ?? []).length;
    const before = calls();
    const r = await post("/api/action", { action: "account.login.cancel", name: "default" });
    ok("an action that looks nothing up does not read the registry", r.status === 200 && calls() === before, `registry reads: +${calls() - before}`);
  }
  {
    fs.writeFileSync(path.join(FX, "slow"), "");
    const slow = fetch(BASE + "/api/state?refresh=1").then((r) => r.json());
    await sleep(300);
    const rm = await post("/api/action", { action: "binding.remove", dir: path.join(ROOT, "bind2") });
    const fresh = await fetch(BASE + "/api/state?refresh=1").then((r) => r.json());
    await slow;
    fs.rmSync(path.join(FX, "slow"));
    ok("a read that started before a change is not served after it", rm.status === 200 && fresh.data.bindings.length === 1, `bindings after unbind: ${fresh.data.bindings.length} (want 1)`);
  }
  {
    fs.writeFileSync(path.join(FX, "die-early"), "");
    const r = await post("/api/action", { action: "provider.save", name: "kimi", doc: { agent: "claude", env: { PAD: "x".repeat(190000) }, models: {} } }).catch((e) => ({ status: `ERR ${e.cause?.code}` }));
    await sleep(800);
    const alive = await fetch(BASE).then((x) => x.ok).catch(() => false);
    const epipe = /EPIPE/.test(fs.readFileSync(path.join(FX, "server.log"), "utf8"));
    ok("a core that exits before reading its input leaves no uncaught EPIPE", alive && r.status === 422 && !epipe, `status ${r.status}, server ${alive ? "alive" : "down"}, EPIPE logged: ${epipe}`);
  }
} finally {
  await browser.close().catch(() => {});
  server.kill();
  fs.rmSync(ROOT, { recursive: true, force: true });
}

for (const r of results) console.log(`${r.pass ? "PASS" : "FAIL"}  ${r.name}${r.note ? `  (${r.note})` : ""}`);
const failed = results.filter((r) => !r.pass).length;
console.log(failed ? `\n${failed} of ${results.length} FAILED` : "\nALL OK");
process.exit(failed ? 1 : 0);
