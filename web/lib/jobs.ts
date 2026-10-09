import { spawn, type ChildProcess } from "node:child_process";
import { CORE, invalidate } from "./zorua";
import type { LoginJob } from "./types";

const MAX_OUTPUT = 4000;
const TIMEOUT_MS = 10 * 60_000;

type Entry = { job: LoginJob; child: ChildProcess | null };
const g = globalThis as unknown as { __zoruaJobs?: Map<string, Entry> };
const jobs = (g.__zoruaJobs ??= new Map<string, Entry>());

function append(e: Entry, chunk: Buffer) {
  e.job.output = (e.job.output + chunk.toString()).slice(-MAX_OUTPUT);
  e.job.urls = [...new Set(e.job.output.match(/https?:\/\/[^\s"'<>)]+/g) ?? [])].slice(0, 3);
}

/** Start `zorua login <name>` (it opens the browser itself) and track it. One job per account. */
export function startLogin(name: string): LoginJob {
  const running = jobs.get(name);
  if (running?.job.status === "running") return running.job;
  const job: LoginJob = { name, status: "running", output: "", urls: [], startedAt: Date.now() };
  const entry: Entry = { job, child: null };
  jobs.set(name, entry);
  const child = spawn("python3", [CORE, "login", name], { stdio: ["ignore", "pipe", "pipe"] });
  entry.child = child;
  child.stdout.on("data", (b: Buffer) => append(entry, b));
  child.stderr.on("data", (b: Buffer) => append(entry, b));
  const timer = setTimeout(() => child.kill("SIGTERM"), TIMEOUT_MS);
  child.on("error", (err) => {
    clearTimeout(timer);
    job.status = "failed";
    job.output += `\n${err.message}`;
  });
  child.on("close", (code) => {
    clearTimeout(timer);
    job.status = code === 0 ? "done" : "failed";
    entry.child = null;
    invalidate();
  });
  return job;
}

export function getLogin(name: string): LoginJob | null {
  return jobs.get(name)?.job ?? null;
}

export function cancelLogin(name: string): boolean {
  const e = jobs.get(name);
  if (!e?.child) return false;
  e.child.kill("SIGTERM");
  return true;
}
