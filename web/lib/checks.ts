import type { Check } from "./types";
import { runCore, ZoruaError } from "./zorua";

// Kept on globalThis (like the state cache) so every route module sees the same results.
const g = globalThis as unknown as { __zoruaChecks?: Map<string, Check> };
const store = (g.__zoruaChecks ??= new Map<string, Check>());

/** Run `zorua provider check <name> --json` and remember the result until the server restarts. */
export async function runCheck(name: string): Promise<Check> {
  const out = await runCore(["provider", "check", name, "--json"], { timeout: 40_000 });
  let c: Check;
  try {
    c = JSON.parse(out) as Check;
  } catch {
    throw new ZoruaError("zorua returned invalid JSON");
  }
  store.set(name, c);
  return c;
}

/** The remembered results for providers that still exist. */
export function knownChecks(names: string[]): Record<string, Check> {
  const out: Record<string, Check> = {};
  for (const n of names) {
    const c = store.get(n);
    if (c) out[n] = c;
  }
  return out;
}

export function forget(name: string) {
  store.delete(name);
}
