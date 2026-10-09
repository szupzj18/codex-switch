import { execFile } from "node:child_process";
import { homedir } from "node:os";
import path from "node:path";
import type { ZoruaState } from "./types";

const CORE = process.env.ZORUA_CORE ?? path.join(homedir(), ".zorua", "zorua_core.py");
const TTL_MS = 30_000;
const MIN_FORCE_GAP_MS = 5_000;

let cache: { at: number; data: ZoruaState } | null = null;
let inflight: Promise<ZoruaState> | null = null;
let lastError: string | null = null;

function run(): Promise<ZoruaState> {
  return new Promise((resolve, reject) => {
    execFile(
      "python3",
      [CORE, "usage", "--json"],
      { timeout: 60_000, maxBuffer: 5 * 1024 * 1024, env: process.env },
      (err, stdout, stderr) => {
        if (err) return reject(new Error((stderr || err.message).trim().slice(0, 400)));
        try {
          resolve(JSON.parse(stdout) as ZoruaState);
        } catch {
          reject(new Error("zorua returned invalid JSON"));
        }
      },
    );
  });
}

function refresh(): Promise<ZoruaState> {
  if (!inflight) {
    inflight = run()
      .then((data) => {
        cache = { at: Date.now(), data };
        lastError = null;
        return data;
      })
      .catch((e: Error) => {
        lastError = e.message;
        throw e;
      })
      .finally(() => {
        inflight = null;
      });
  }
  return inflight;
}

/** Stale-while-revalidate: an old snapshot is served at once and refreshed in the background. */
export async function getState(force: boolean) {
  const age = cache ? Date.now() - cache.at : Infinity;
  if (!cache || (force && age > MIN_FORCE_GAP_MS)) {
    const data = await refresh();
    return { data, stale: false, error: null as string | null };
  }
  const stale = age > TTL_MS;
  if (stale) refresh().catch(() => {});
  return { data: cache.data, stale, error: lastError };
}
