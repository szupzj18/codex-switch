import { stat } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { forget } from "./checks";
import { cancelLogin, startLogin } from "./jobs";
import type { LoginJob, ZoruaState } from "./types";
import { invalidate, readRegistry, runCore, ZoruaError } from "./zorua";

export class BadRequest extends Error {}

const NAME = /^[A-Za-z0-9_-]{1,32}$/;
const MODEL = /^[\w.:/\-[\]]{1,100}$/;

type Agent = "codex" | "claude";
export type ActionResult = { ok: true; message: string; job?: LoginJob };

function str(v: unknown, what: string, max = 500): string {
  if (typeof v !== "string" || v.length === 0 || v.length > max || /[\0\r\n]/.test(v)) {
    throw new BadRequest(`${what} is missing or invalid`);
  }
  return v;
}

function name(v: unknown): string {
  const n = str(v, "name", 32);
  if (!NAME.test(n)) throw new BadRequest("name may only use letters, digits, '-' and '_'");
  return n;
}

function agent(v: unknown): Agent {
  if (v !== "codex" && v !== "claude") throw new BadRequest("agent must be codex or claude");
  return v;
}

function baseUrl(v: unknown): string {
  const raw = str(v, "base URL", 300);
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    throw new BadRequest("base URL is not a valid URL");
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") throw new BadRequest("base URL must be http or https");
  if (u.username || u.password) throw new BadRequest("base URL must not contain credentials");
  return raw;
}

async function directory(v: unknown): Promise<string> {
  const raw = str(v, "directory", 1000);
  if (!path.isAbsolute(raw)) throw new BadRequest("directory must be an absolute path");
  const d = path.resolve(raw);
  const s = await stat(d).catch(() => null);
  if (!s?.isDirectory()) throw new BadRequest("directory does not exist");
  return d;
}

/** Only directories that Zorua itself created (~/.codex-<name> / ~/.claude-<name>) may be purged. */
function purgeable(home: string): boolean {
  return path.dirname(home) === homedir() && /^\.(codex|claude)-[A-Za-z0-9_-]+$/.test(path.basename(home));
}

export async function perform(input: unknown): Promise<ActionResult> {
  if (typeof input !== "object" || input === null) throw new BadRequest("invalid request");
  const b = input as Record<string, unknown>;
  // Read lazily: only the actions that look something up pay for the extra process.
  let loaded: Promise<ZoruaState> | undefined;
  const registry = () => (loaded ??= readRegistry());
  const run = async (args: string[], extra: Parameters<typeof runCore>[1] = {}) => {
    try {
      await runCore(args, { timeout: 30_000, ...extra });
    } finally {
      invalidate();
    }
  };

  switch (b.action) {
    case "account.add": {
      const n = name(b.name);
      const a = agent(b.agent);
      await run(["add", ...(a === "claude" ? ["--claude"] : []), n, "--no-login"]);
      if (b.login === true) return { ok: true, message: `added ${n}; sign-in started`, job: startLogin(n) };
      return { ok: true, message: `added ${n}; run sign-in when you are ready` };
    }
    case "account.login": {
      const n = name(b.name);
      if (!(await registry()).accounts.some((x) => x.name === n)) throw new BadRequest(`unknown account '${n}'`);
      return { ok: true, message: `sign-in started for ${n}`, job: startLogin(n) };
    }
    case "account.login.cancel": {
      const n = name(b.name);
      return { ok: true, message: cancelLogin(n) ? "sign-in cancelled" : "no sign-in is running" };
    }
    case "account.remove": {
      const n = name(b.name);
      if (n === "default") throw new BadRequest("default is built-in and cannot be removed");
      const acc = (await registry()).accounts.find((x) => x.name === n);
      if (!acc) throw new BadRequest(`unknown account '${n}'`);
      const purge = b.purge === true;
      if (purge) {
        if (b.confirm !== n) throw new BadRequest("type the account name to confirm deleting its data");
        if (!purgeable(acc.home)) throw new BadRequest(`refusing to delete ${acc.home}: not a directory Zorua created`);
      }
      await run(["rm", n, ...(purge ? ["--purge"] : [])]);
      return { ok: true, message: purge ? `removed ${n} and deleted its data` : `removed ${n}; data kept in ${acc.home}` };
    }
    case "provider.add": {
      const a = agent(b.agent);
      const n = name(b.name);
      const url = baseUrl(b.baseUrl);
      const key = str(b.key, "key", 512);
      const model = b.model === undefined || b.model === "" ? null : str(b.model, "model", 100);
      if (model && !MODEL.test(model)) throw new BadRequest("model id has unexpected characters");
      if (a === "codex" && !model) throw new BadRequest("a Codex provider needs a model");
      const args =
        a === "codex"
          ? ["provider", "add", n, "--codex", "--base-url", url, "--key-env", "ZORUA_WEB_KEY", "--model", model!, "--wire-api", "responses"]
          : ["provider", "add", n, "--base-url", url, "--key-env", "ZORUA_WEB_KEY", ...(model ? ["--model", `default=${model}`] : [])];
      try {
        await run(args, { env: { ZORUA_WEB_KEY: key } });
      } catch (e) {
        if (e instanceof ZoruaError) throw new ZoruaError(e.message.split(key).join("***"));
        throw e;
      }
      return { ok: true, message: `added provider ${n}` };
    }
    case "provider.save": {
      const n = name(b.name);
      if (!(await registry()).providers.some((p) => p.name === n)) throw new BadRequest(`unknown provider '${n}'`);
      if (typeof b.doc !== "object" || b.doc === null || Array.isArray(b.doc)) throw new BadRequest("doc must be an object");
      const input = JSON.stringify(b.doc);
      if (input.length > 200_000) throw new BadRequest("document is too large");
      await run(["provider", "put", n], { input });
      forget(n);
      return { ok: true, message: `saved provider ${n}` };
    }
    case "provider.remove": {
      const n = name(b.name);
      if (!(await registry()).providers.some((p) => p.name === n)) throw new BadRequest(`unknown provider '${n}'`);
      await run(["provider", "rm", n]);
      forget(n);
      return { ok: true, message: `removed provider ${n}` };
    }
    case "binding.add": {
      const n = name(b.name);
      const dir = await directory(b.dir);
      if (!(await registry()).accounts.some((x) => x.name === n) && !(await registry()).providers.some((p) => p.name === n)) {
        throw new BadRequest(`unknown account or provider '${n}'`);
      }
      await run(["bind", n], { cwd: dir });
      return { ok: true, message: `bound ${dir} to ${n}` };
    }
    case "binding.remove": {
      const dir = str(b.dir, "directory", 1000);
      if (!(await registry()).bindings.some((x) => x.dir === dir)) throw new BadRequest("no such binding");
      await run(["unbind", dir]);
      return { ok: true, message: `unbound ${dir}` };
    }
    default:
      throw new BadRequest("unknown action");
  }
}
