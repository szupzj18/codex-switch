"use client";

import { useCallback, useEffect, useState } from "react";
import type { Account, Binding, Provider, StateResponse, UsageWindow } from "@/lib/types";
import { act, AddAccountForm, AddBindingForm, AddProviderForm, LoginBanner, Modal, RemoveAccountForm } from "./manage";

const POLL_MS = 30_000;

const PLAN_STYLE: Record<string, string> = {
  pro: "text-accent",
  plus: "text-accent",
  promax: "text-violet",
  max: "text-violet",
  team: "text-sky-300",
  enterprise: "text-sky-300",
};

function windowLabel(s: number | null) {
  if (!s) return "?";
  return s < 86400 ? `${Math.round(s / 3600)}H` : `${Math.round(s / 86400)}D`;
}

function span(s: number) {
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d && h) return `${d}d${h}h`;
  if (d) return `${d}d`;
  if (h) return `${h}h${m}m`;
  return `${m}m`;
}

function ago(s: number) {
  return s < 3600 ? `${Math.floor(s / 60)}m ago` : `${span(s)} ago`;
}

function barColor(p: number) {
  return p >= 80 ? "bg-danger" : p >= 50 ? "bg-warn" : "bg-accent";
}

function Bar({ w }: { w: UsageWindow }) {
  const p = Math.max(0, Math.min(100, w.used_percent ?? 0));
  return (
    <div className="min-w-0">
      <div className="flex items-baseline justify-between gap-2 text-xs">
        <span className="text-dim">{windowLabel(w.window_seconds)}</span>
        <span className="tabular-nums">{p}%</span>
      </div>
      <div
        className="mt-1 h-1.5 overflow-hidden rounded-full bg-line"
        role="progressbar"
        aria-valuenow={p}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={`${windowLabel(w.window_seconds)} usage`}
      >
        <div className={`h-full ${barColor(p)}`} style={{ width: `${p}%` }} />
      </div>
      {w.reset_after_seconds != null && (
        <div className="mt-1 text-[11px] text-dim">resets in {span(w.reset_after_seconds)}</div>
      )}
    </div>
  );
}

function AccountRow({ a, onLogin, onRemove }: { a: Account; onLogin: () => void; onRemove: () => void }) {
  const ws = a.usage.windows;
  let note: string | null = null;
  if (a.usage.error) note = a.usage.error;
  else if (a.state !== "ok") note = a.state === "apikey" ? "API key login" : a.state === "none" ? "not signed in" : a.state;
  else if (ws.length === 0) note = a.agent === "claude" ? `no usage yet — run 'zorua hook install ${a.name}', then use claude once` : "no usage data";
  return (
    <li className="grid grid-cols-1 gap-3 border-b border-line px-4 py-3 last:border-b-0 sm:grid-cols-[minmax(0,1.2fr)_minmax(0,2fr)]">
      <div className="min-w-0">
        <div className="flex flex-wrap items-baseline gap-x-2">
          <span className="font-bold text-accent">{a.name}</span>
          {a.plan && <span className={`text-xs ${PLAN_STYLE[a.plan] ?? "text-fg"}`}>{a.plan}</span>}
        </div>
        <div className="truncate text-xs text-dim" title={a.email ?? undefined}>
          {a.email ?? "—"}
        </div>
        <div className="truncate text-[11px] text-dim/70" title={a.home}>
          {a.home}
        </div>
        <div className="mt-2 flex gap-3 text-[11px]">
          <button type="button" onClick={onLogin} className="text-dim underline hover:text-accent">
            sign in
          </button>
          {a.name !== "default" && (
            <button type="button" onClick={onRemove} className="text-dim underline hover:text-danger">
              remove
            </button>
          )}
        </div>
      </div>
      <div>
        {ws.length > 0 ? (
          <div className="grid grid-cols-2 gap-4">
            {ws.map((w, i) => (
              <Bar key={i} w={w} />
            ))}
          </div>
        ) : (
          <div className="text-xs text-dim">{note}</div>
        )}
        {ws.length > 0 && a.usage.age_seconds != null && (
          <div className="mt-2 text-[11px] text-dim">from its last session, {ago(a.usage.age_seconds)}</div>
        )}
        {ws.length > 0 && note && <div className="mt-2 text-[11px] text-danger">{note}</div>}
      </div>
    </li>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-8">
      <h2 className="mb-3 text-sm before:mr-2 before:text-accent before:content-['#']">{title}</h2>
      <div className="overflow-hidden rounded-[10px] border border-line bg-panel">{children}</div>
    </section>
  );
}

function ProviderRow({ p, onRemove }: { p: Provider; onRemove: () => void }) {
  const models = Object.keys(p.models);
  return (
    <li className="grid grid-cols-1 gap-1 border-b border-line px-4 py-3 last:border-b-0 sm:grid-cols-[minmax(0,1.2fr)_minmax(0,2fr)]">
      <div>
        <span className="font-bold text-accent">{p.name}</span>
        <span className="ml-2 text-xs text-dim">{p.endpoint}</span>
        <button type="button" onClick={onRemove} className="ml-3 text-[11px] text-dim underline hover:text-danger">
          remove
        </button>
      </div>
      <div className="text-xs text-dim">
        {models.length === 0 ? "no model catalog" : `${models.length} model${models.length === 1 ? "" : "s"}: ${models.slice(0, 6).join(", ")}${models.length > 6 ? " …" : ""}`}
      </div>
    </li>
  );
}

function BindingRow({ b, onRemove }: { b: Binding; onRemove: () => void }) {
  return (
    <li className="flex flex-wrap items-baseline gap-x-3 border-b border-line px-4 py-3 last:border-b-0">
      <span className="min-w-0 flex-1 truncate text-sm" title={b.dir}>
        {b.dir}
      </span>
      <span className="text-xs text-accent">→ {b.name}</span>
      <button type="button" onClick={onRemove} className="text-[11px] text-dim underline hover:text-danger">
        unbind
      </button>
    </li>
  );
}

function ConfirmForm({ text, label, body, onDone, onCancel }: { text: string; label: string; body: Record<string, unknown>; onDone: (m: string) => void; onCancel: () => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  return (
    <form
      onSubmit={async (e) => {
        e.preventDefault();
        setBusy(true);
        try {
          onDone((await act(body)).message);
        } catch (err) {
          setError(err instanceof Error ? err.message : String(err));
          setBusy(false);
        }
      }}
    >
      <p className="mb-3 text-xs text-dim">{text}</p>
      {error && <p className="mb-3 rounded-md border border-danger/40 bg-danger/10 px-3 py-2 text-xs text-danger">{error}</p>}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onCancel} className="rounded-md border border-line px-3 py-1.5 text-xs text-dim hover:text-fg">
          cancel
        </button>
        <button type="submit" disabled={busy} className="rounded-md bg-danger px-3 py-1.5 text-xs font-bold text-[#1a0508] disabled:opacity-50">
          {busy ? "working…" : label}
        </button>
      </div>
    </form>
  );
}

type Dialog =
  | { kind: "account" }
  | { kind: "provider" }
  | { kind: "binding" }
  | { kind: "remove-account"; a: Account }
  | { kind: "remove-provider"; name: string }
  | { kind: "unbind"; dir: string };

const ownedDir = (home: string) => /\/\.(codex|claude)-[A-Za-z0-9_-]+$/.test(home);

export default function Dashboard() {
  const [res, setRes] = useState<StateResponse | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [dialog, setDialog] = useState<Dialog | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loginFor, setLoginFor] = useState<string | null>(null);

  const load = useCallback(async (force: boolean) => {
    setLoading(true);
    try {
      const r = await fetch(`/api/state${force ? "?refresh=1" : ""}`, { cache: "no-store" });
      const body = await r.json();
      if (!r.ok) throw new Error(body.error ?? `HTTP ${r.status}`);
      setRes(body as StateResponse);
      setErr(null);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  const finished = (message: string, job?: { name: string }) => {
    setDialog(null);
    setNotice(message);
    if (job) setLoginFor(job.name);
    load(true);
  };
  const onLoginFinished = useCallback(() => load(true), [load]);

  useEffect(() => {
    load(false);
    const t = setInterval(() => load(false), POLL_MS);
    return () => clearInterval(t);
  }, [load]);

  const data = res?.data;
  const codex = data?.accounts.filter((a) => a.agent === "codex") ?? [];
  const claude = data?.accounts.filter((a) => a.agent === "claude") ?? [];
  const cProv = data?.providers.filter((p) => p.agent === "codex") ?? [];
  const aProv = data?.providers.filter((p) => p.agent === "claude") ?? [];

  return (
    <>
      <header className="flex items-center gap-4">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/icon.svg" width={56} height={56} alt="Zorua" className="rounded-xl" />
        <div className="min-w-0 flex-1">
          <div className="text-xs text-accent">$ zorua usage{data ? ` · ${data.version}` : ""}</div>
          <h1 className="text-2xl font-bold leading-tight">
            Accounts <span className="text-accent">&amp; usage</span>
          </h1>
        </div>
        <button
          type="button"
          onClick={() => load(true)}
          disabled={loading}
          className="rounded-md bg-accent px-3 py-1.5 text-xs font-bold text-[#04110e] disabled:opacity-50"
        >
          {loading ? "loading…" : "refresh"}
        </button>
      </header>

      <p className="mt-2 text-xs text-dim" aria-live="polite">
        {res
          ? `updated ${new Date(res.data.generated_at * 1000).toLocaleTimeString()}${res.stale ? " · refreshing" : ""}`
          : "reading accounts…"}
      </p>
      {(err || res?.error) && (
        <p className="mt-2 rounded-md border border-danger/40 bg-danger/10 px-3 py-2 text-xs text-danger">
          {err ?? res?.error}
        </p>
      )}
      {notice && (
        <p className="mt-2 flex items-center rounded-md border border-accent/40 bg-accent/10 px-3 py-2 text-xs text-accent" aria-live="polite">
          {notice}
          <button type="button" className="ml-auto text-dim underline" onClick={() => setNotice(null)}>
            dismiss
          </button>
        </p>
      )}
      {loginFor && <LoginBanner name={loginFor} onFinished={onLoginFinished} />}

      <div className="mt-4 flex flex-wrap gap-2">
        {([["account", "+ account"], ["provider", "+ provider"], ["binding", "+ binding"]] as const).map(([k, label]) => (
          <button key={k} type="button" onClick={() => setDialog({ kind: k })} className="rounded-md border border-accent px-3 py-1.5 text-xs text-accent hover:bg-accent/10">
            {label}
          </button>
        ))}
      </div>

      {data && (
        <>
          {(
            [
              ["Codex", codex],
              ["Claude Code", claude],
            ] as const
          ).map(([title, list]) => (
            <Panel key={title} title={title}>
              <ul>
                {list.length ? (
                  list.map((a) => (
                    <AccountRow
                      key={a.name}
                      a={a}
                      onLogin={async () => {
                        try {
                          const r = await act({ action: "account.login", name: a.name });
                          finished(r.message, r.job);
                        } catch (e) {
                          setNotice(e instanceof Error ? e.message : String(e));
                        }
                      }}
                      onRemove={() => setDialog({ kind: "remove-account", a })}
                    />
                  ))
                ) : (
                  <li className="px-4 py-3 text-xs text-dim">no accounts</li>
                )}
              </ul>
            </Panel>
          ))}
          <Panel title="Providers">
            <ul>
              {aProv.length + cProv.length > 0 ? (
                [...aProv, ...cProv].map((p) => <ProviderRow key={`${p.agent}:${p.name}`} p={p} onRemove={() => setDialog({ kind: "remove-provider", name: p.name })} />)
              ) : (
                <li className="px-4 py-3 text-xs text-dim">no providers</li>
              )}
            </ul>
          </Panel>
          <Panel title="Directory bindings">
            <ul>
              {data.bindings.length ? (
                data.bindings.map((b) => <BindingRow key={`${b.dir}:${b.name}`} b={b} onRemove={() => setDialog({ kind: "unbind", dir: b.dir })} />)
              ) : (
                <li className="px-4 py-3 text-xs text-dim">no bindings — a bound directory switches to its account when you cd into it</li>
              )}
            </ul>
          </Panel>
        </>
      )}

      {dialog?.kind === "account" && (
        <Modal title="Add account" onClose={() => setDialog(null)}>
          <AddAccountForm onDone={(r) => finished(r.message, r.job)} onCancel={() => setDialog(null)} />
        </Modal>
      )}
      {dialog?.kind === "provider" && (
        <Modal title="Add provider" onClose={() => setDialog(null)}>
          <AddProviderForm onDone={(r) => finished(r.message)} onCancel={() => setDialog(null)} />
        </Modal>
      )}
      {dialog?.kind === "binding" && data && (
        <Modal title="Bind a directory" onClose={() => setDialog(null)}>
          <AddBindingForm data={data} onDone={(r) => finished(r.message)} onCancel={() => setDialog(null)} />
        </Modal>
      )}
      {dialog?.kind === "remove-account" && (
        <Modal title={`Remove ${dialog.a.name}`} onClose={() => setDialog(null)}>
          <RemoveAccountForm name={dialog.a.name} home={dialog.a.home} canPurge={ownedDir(dialog.a.home)} onDone={(r) => finished(r.message)} onCancel={() => setDialog(null)} />
        </Modal>
      )}
      {dialog?.kind === "remove-provider" && (
        <Modal title={`Remove provider ${dialog.name}`} onClose={() => setDialog(null)}>
          <ConfirmForm text="The provider and its stored key are deleted from Zorua." label="remove" body={{ action: "provider.remove", name: dialog.name }} onDone={finished} onCancel={() => setDialog(null)} />
        </Modal>
      )}
      {dialog?.kind === "unbind" && (
        <Modal title="Unbind directory" onClose={() => setDialog(null)}>
          <ConfirmForm text={`Stop switching automatically in ${dialog.dir}.`} label="unbind" body={{ action: "binding.remove", dir: dialog.dir }} onDone={finished} onCancel={() => setDialog(null)} />
        </Modal>
      )}
      <footer className="mt-10 text-xs text-dim">
        Data comes from <code className="text-fg">zorua usage --json</code>; changes run the matching <code className="text-fg">zorua</code> command. Tokens and provider keys never reach this page.
      </footer>
    </>
  );
}
