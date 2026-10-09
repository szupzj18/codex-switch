"use client";

import { useEffect, useRef, useState } from "react";
import type { LoginJob, ZoruaState } from "@/lib/types";
import { Icon } from "./icons";
import { alertDanger, fieldCls as field, ghostBtn as ghost, primaryBtn as primary } from "./ui";

export async function act(body: Record<string, unknown>): Promise<{ message: string; job?: LoginJob }> {
  const r = await fetch("/api/action", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Zorua-Web": "1" },
    body: JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data.error ?? `HTTP ${r.status}`);
  return data;
}

export function Modal({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open) d.showModal();
  }, []);
  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onClick={(e) => e.target === ref.current && ref.current?.close()}
      className="m-auto max-h-[90vh] w-[min(92vw,30rem)] rounded-2xl border border-line-strong bg-panel p-0 text-fg shadow-pop backdrop:bg-black/60 backdrop:backdrop-blur-sm open:animate-pop"
    >
      <div className="p-5">
        <div className="mb-4 flex items-center justify-between gap-3">
          <h2 className="text-base font-semibold tracking-tight">{title}</h2>
          <button type="button" onClick={() => ref.current?.close()} aria-label="Close" className="-mr-1 rounded-lg p-1 text-dim hover:text-fg">
            <Icon name="close" />
          </button>
        </div>
        {children}
      </div>
    </dialog>
  );
}

function Labeled({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="mb-3 block text-xs text-dim">
      <span className="mb-1 block">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-[11px] text-dim/70">{hint}</span>}
    </label>
  );
}

function useSubmit(onDone: (r: { message: string; job?: LoginJob }) => void) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const submit = async (body: Record<string, unknown>) => {
    setBusy(true);
    setError(null);
    try {
      onDone(await act(body));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };
  return { busy, error, submit };
}

type Done = (r: { message: string; job?: LoginJob }) => void;

function Actions({ busy, error, label, onCancel, disabled }: { busy: boolean; error: string | null; label: string; onCancel: () => void; disabled?: boolean }) {
  return (
    <>
      {error && <p className={`mb-3 ${alertDanger}`}>{error}</p>}
      <div className="flex justify-end gap-2">
        <button type="button" className={ghost} onClick={onCancel}>
          cancel
        </button>
        <button type="submit" className={primary} disabled={busy || disabled}>
          {busy ? "working…" : label}
        </button>
      </div>
    </>
  );
}

export function AddAccountForm({ onDone, onCancel }: { onDone: Done; onCancel: () => void }) {
  const [name, setName] = useState("");
  const [agent, setAgent] = useState("codex");
  const [login, setLogin] = useState(true);
  const { busy, error, submit } = useSubmit(onDone);
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        submit({ action: "account.add", name, agent, login });
      }}
    >
      <Labeled label="agent">
        <select className={field} value={agent} onChange={(e) => setAgent(e.target.value)}>
          <option value="codex">Codex CLI</option>
          <option value="claude">Claude Code</option>
        </select>
      </Labeled>
      <Labeled label="name" hint="letters, digits, - and _; becomes ~/.codex-<name> or ~/.claude-<name>">
        <input className={field} value={name} onChange={(e) => setName(e.target.value)} placeholder="work" required maxLength={32} pattern="[A-Za-z0-9_\-]+" autoFocus />
      </Labeled>
      <label className="mb-4 flex items-center gap-2 text-xs text-dim">
        <input type="checkbox" checked={login} onChange={(e) => setLogin(e.target.checked)} className="accent-accent" />
        start the browser sign-in right after adding
      </label>
      <Actions busy={busy} error={error} label="add account" onCancel={onCancel} />
    </form>
  );
}

export function AddProviderForm({ onDone, onCancel }: { onDone: Done; onCancel: () => void }) {
  const [agent, setAgent] = useState("claude");
  const [name, setName] = useState("");
  const [baseUrl, setBaseUrl] = useState("");
  const [key, setKey] = useState("");
  const [model, setModel] = useState("");
  const { busy, error, submit } = useSubmit(onDone);
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        submit({ action: "provider.add", agent, name, baseUrl, key, model });
      }}
      autoComplete="off"
    >
      <Labeled label="agent">
        <select className={field} value={agent} onChange={(e) => setAgent(e.target.value)}>
          <option value="claude">Claude Code (Anthropic-style endpoint)</option>
          <option value="codex">Codex CLI (Responses endpoint)</option>
        </select>
      </Labeled>
      <Labeled label="name">
        <input className={field} value={name} onChange={(e) => setName(e.target.value)} placeholder="kimi" required maxLength={32} pattern="[A-Za-z0-9_\-]+" autoFocus />
      </Labeled>
      <Labeled label="base URL">
        <input className={field} value={baseUrl} onChange={(e) => setBaseUrl(e.target.value)} placeholder="https://api.moonshot.cn/anthropic" required type="url" />
      </Labeled>
      <Labeled label="API key" hint="stored by zorua in its own providers.json (mode 0600); never shown again">
        <input className={field} value={key} onChange={(e) => setKey(e.target.value)} type="password" required autoComplete="new-password" />
      </Labeled>
      <Labeled label={agent === "codex" ? "model (required)" : "model (optional)"}>
        <input className={field} value={model} onChange={(e) => setModel(e.target.value)} placeholder={agent === "codex" ? "gpt-6.1-sol" : "kimi-k2"} required={agent === "codex"} />
      </Labeled>
      <Actions busy={busy} error={error} label="add provider" onCancel={onCancel} />
    </form>
  );
}

export function AddBindingForm({ data, onDone, onCancel }: { data: ZoruaState; onDone: Done; onCancel: () => void }) {
  const targets = [...data.accounts.map((a) => a.name), ...data.providers.map((p) => p.name)];
  const [dir, setDir] = useState("");
  const [name, setName] = useState(targets[0] ?? "");
  const { busy, error, submit } = useSubmit(onDone);
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        submit({ action: "binding.add", dir, name });
      }}
    >
      <Labeled label="project directory" hint="absolute path; the binding also covers subdirectories">
        <input className={field} value={dir} onChange={(e) => setDir(e.target.value)} placeholder="/Users/you/code/project" required autoFocus />
      </Labeled>
      <Labeled label="account or provider">
        <select className={field} value={name} onChange={(e) => setName(e.target.value)}>
          {targets.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
      </Labeled>
      <Actions busy={busy} error={error} label="bind" onCancel={onCancel} />
    </form>
  );
}

export function RemoveAccountForm({ name, home, canPurge, onDone, onCancel }: { name: string; home: string; canPurge: boolean; onDone: Done; onCancel: () => void }) {
  const [purge, setPurge] = useState(false);
  const [confirm, setConfirm] = useState("");
  const { busy, error, submit } = useSubmit(onDone);
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        submit({ action: "account.remove", name, purge, confirm });
      }}
    >
      <p className="mb-3 text-xs text-dim">
        Remove <b className="text-fg">{name}</b> from Zorua. Its data directory <code className="text-fg">{home}</code> is kept unless you tick the box below.
      </p>
      {canPurge ? (
        <label className="mb-3 flex items-start gap-2 text-xs text-dim">
          <input type="checkbox" checked={purge} onChange={(e) => setPurge(e.target.checked)} className="mt-0.5 accent-danger" />
          <span>also delete the data directory (sign-in, history). This cannot be undone.</span>
        </label>
      ) : (
        <p className="mb-3 text-[11px] text-dim/70">This directory was not created by Zorua, so it can only be unregistered here.</p>
      )}
      {purge && (
        <Labeled label={`type "${name}" to confirm`}>
          <input className={field} value={confirm} onChange={(e) => setConfirm(e.target.value)} autoFocus />
        </Labeled>
      )}
      <Actions busy={busy} error={error} label={purge ? "remove and delete" : "remove"} onCancel={onCancel} disabled={purge && confirm !== name} />
    </form>
  );
}

/** Follows a running sign-in: shows the link the CLI printed and lets you cancel. */
export function LoginBanner({ name, onFinished }: { name: string; onFinished: () => void }) {
  const [job, setJob] = useState<LoginJob | null>(null);
  useEffect(() => {
    let stop = false;
    const tick = async () => {
      const r = await fetch(`/api/login?name=${encodeURIComponent(name)}`, { cache: "no-store" }).catch(() => null);
      const j = (await r?.json().catch(() => null))?.job as LoginJob | null | undefined;
      if (stop || !j) return;
      setJob(j);
      if (j.status === "running") timer = setTimeout(tick, 1500);
      else onFinished();
    };
    let timer = setTimeout(tick, 300);
    return () => {
      stop = true;
      clearTimeout(timer);
    };
  }, [name, onFinished]);
  if (!job) return null;
  const tone = job.status === "failed" ? "border-danger/40 bg-danger/10" : job.status === "done" ? "border-accent/40 bg-accent/10" : "border-warn/40 bg-warn/10";
  return (
    <div className={`mt-3 rounded-lg border px-3 py-2 text-xs ${tone}`} aria-live="polite">
      <div className="flex items-center gap-2">
        <b>
          sign-in {job.name}: {job.status === "running" ? "waiting for the browser…" : job.status === "done" ? "done" : "failed"}
        </b>
        {job.status === "running" && (
          <button type="button" className="ml-auto text-dim underline" onClick={() => act({ action: "account.login.cancel", name })}>
            cancel
          </button>
        )}
      </div>
      {job.urls.map((u) => (
        <a key={u} href={u} target="_blank" rel="noreferrer" className="mt-1 block truncate text-accent underline">
          {u}
        </a>
      ))}
      {job.status !== "done" && job.output && <pre className="mt-2 max-h-28 overflow-auto whitespace-pre-wrap p-0 text-[11px] text-dim">{job.output.slice(-600)}</pre>}
    </div>
  );
}
