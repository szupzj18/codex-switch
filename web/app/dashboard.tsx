"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { Account, Check, StateResponse } from "@/lib/types";
import { AccountView } from "./account-view";
import { checkProvider, newest } from "./check";
import { act, AddAccountForm, AddBindingForm, AddProviderForm, LoginBanner, Modal, RemoveAccountForm } from "./manage";
import { Overview } from "./overview";
import { ProviderPage } from "./provider-editor";
import { Sidebar } from "./sidebar";
import { formatHash, parseHash, type View } from "./view";

const POLL_MS = 30_000;
const HOME = "#/";

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
        <button type="submit" disabled={busy} className="rounded-md bg-danger px-3 py-1.5 text-xs font-bold text-on-danger disabled:opacity-50">
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
  const [view, setView] = useState<View>({ kind: "overview" });
  const [checks, setChecks] = useState<Record<string, Check>>({});
  const [checking, setChecking] = useState<Set<string>>(new Set());
  const dirty = useRef(false);
  const applied = useRef(HOME);

  const load = useCallback(async (force: boolean) => {
    setLoading(true);
    try {
      const r = await fetch(`/api/state${force ? "?refresh=1" : ""}`, { cache: "no-store" });
      const body = await r.json();
      if (!r.ok) throw new Error(body.error ?? `HTTP ${r.status}`);
      setRes(body as StateResponse);
      setChecks((cur) => newest(cur, (body as StateResponse).checks ?? {}));
      setErr(null);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  // The view lives in the URL hash (#/provider/kimi): links, back and reload all work.
  useEffect(() => {
    applied.current = location.hash || HOME;
    setView(parseHash(location.hash));
    const onHash = () => {
      const h = location.hash || HOME;
      if (h === applied.current) return;
      if (dirty.current && !window.confirm("Discard unsaved changes?")) {
        history.replaceState(null, "", applied.current);
        return;
      }
      dirty.current = false;
      applied.current = h;
      setView(parseHash(h));
    };
    const onUnload = (e: BeforeUnloadEvent) => {
      if (dirty.current) e.preventDefault();
    };
    window.addEventListener("hashchange", onHash);
    window.addEventListener("beforeunload", onUnload);
    return () => {
      window.removeEventListener("hashchange", onHash);
      window.removeEventListener("beforeunload", onUnload);
    };
  }, []);
  const go = useCallback((v: View) => {
    location.hash = formatHash(v);
  }, []);
  const setDirty = useCallback((d: boolean) => {
    dirty.current = d;
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
  const startLogin = async (a: Account) => {
    try {
      const r = await act({ action: "account.login", name: a.name });
      finished(r.message, r.job);
    } catch (e) {
      setNotice(e instanceof Error ? e.message : String(e));
    }
  };

  const check = async (name: string) => {
    setChecking((cur) => new Set(cur).add(name));
    try {
      const c = await checkProvider(name);
      setChecks((cur) => ({ ...cur, [name]: c }));
    } catch (e) {
      setNotice(`check ${name}: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setChecking((cur) => {
        const next = new Set(cur);
        next.delete(name);
        return next;
      });
    }
  };
  const checkAll = async () => {
    for (const p of data?.providers ?? []) await check(p.name);
  };
  // A saved provider has a new endpoint or key, so its last result no longer applies.
  const dropCheck = (name: string) =>
    setChecks((cur) => {
      const { [name]: _gone, ...rest } = cur;
      return rest;
    });

  const account = view.kind === "account" ? data?.accounts.find((a) => a.name === view.name) : undefined;
  const provider = view.kind === "provider" ? data?.providers.find((p) => p.name === view.name) : undefined;
  const title = view.kind === "overview" ? "Overview" : view.kind === "account" ? `Account · ${view.name}` : `Provider · ${view.name}`;

  return (
    <div className="mx-auto grid max-w-[1800px] gap-6 px-4 pb-16 pt-6 lg:grid-cols-[15rem_minmax(0,1fr)] lg:px-6">
      <Sidebar data={data} view={view} onGo={go} />

      <main className="min-w-0">
        <header className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <div className="min-w-0 flex-1">
            <div className="text-xs text-accent">$ zorua usage{data ? ` · ${data.version}` : ""}</div>
            <h1 className="truncate text-2xl font-bold leading-tight">{title}</h1>
          </div>
          <div className="flex flex-wrap gap-2">
            {([["account", "+ account"], ["provider", "+ provider"], ["binding", "+ binding"]] as const).map(([k, label]) => (
              <button key={k} type="button" onClick={() => setDialog({ kind: k })} className="rounded-md border border-accent px-3 py-1.5 text-xs text-accent hover:bg-accent/10">
                {label}
              </button>
            ))}
            <button type="button" onClick={() => load(true)} disabled={loading} className="rounded-md bg-accent px-3 py-1.5 text-xs font-bold text-on-accent disabled:opacity-50">
              {loading ? "loading…" : "refresh"}
            </button>
          </div>
        </header>

        <p className="mt-2 text-xs text-dim" aria-live="polite">
          {res ? `updated ${new Date(res.data.generated_at * 1000).toLocaleTimeString()}${res.stale ? " · refreshing" : ""}` : "reading accounts…"}
        </p>
        {(err || res?.error) && <p className="mt-2 rounded-md border border-danger/40 bg-danger/10 px-3 py-2 text-xs text-danger">{err ?? res?.error}</p>}
        {notice && (
          <p className="mt-2 flex items-center rounded-md border border-accent/40 bg-accent/10 px-3 py-2 text-xs text-accent" aria-live="polite">
            {notice}
            <button type="button" className="ml-auto text-dim underline" onClick={() => setNotice(null)}>
              dismiss
            </button>
          </p>
        )}
        {loginFor && <LoginBanner name={loginFor} onFinished={onLoginFinished} />}

        <div className="mt-6">
          {data && view.kind === "overview" && (
            <Overview
              data={data}
              checks={checks}
              checking={checking}
              onOpen={go}
              onLogin={startLogin}
              onCheck={check}
              onCheckAll={checkAll}
              onRemoveAccount={(a) => setDialog({ kind: "remove-account", a })}
              onRemoveProvider={(name) => setDialog({ kind: "remove-provider", name })}
              onUnbind={(dir) => setDialog({ kind: "unbind", dir })}
            />
          )}
          {data && view.kind === "account" &&
            (account ? (
              <AccountView a={account} bindings={data.bindings.filter((b) => b.name === account.name)} onLogin={() => startLogin(account)} onRemove={() => setDialog({ kind: "remove-account", a: account })} />
            ) : (
              <NotFound what={`account '${view.name}'`} onBack={() => go({ kind: "overview" })} />
            ))}
          {data && view.kind === "provider" &&
            (provider ? (
              <ProviderPage
                key={provider.name}
                name={provider.name}
                endpoint={provider.endpoint}
                check={checks[provider.name]}
                checking={checking.has(provider.name)}
                onCheck={() => check(provider.name)}
                onDirty={setDirty}
                onSaved={() => {
                  dropCheck(provider.name);
                  load(true);
                }}
                onRemove={() => setDialog({ kind: "remove-provider", name: provider.name })}
              />
            ) : (
              <NotFound what={`provider '${view.name}'`} onBack={() => go({ kind: "overview" })} />
            ))}
        </div>

        <footer className="mt-10 text-xs text-dim">
          Data comes from <code className="text-fg">zorua usage --json</code>; changes run the matching <code className="text-fg">zorua</code> command. Account tokens never reach this page; a provider key is sent only when you press “show keys”.
        </footer>
      </main>

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
          <RemoveAccountForm
            name={dialog.a.name}
            home={dialog.a.home}
            canPurge={ownedDir(dialog.a.home)}
            onDone={(r) => {
              finished(r.message);
              if (view.kind === "account" && view.name === dialog.a.name) go({ kind: "overview" });
            }}
            onCancel={() => setDialog(null)}
          />
        </Modal>
      )}
      {dialog?.kind === "remove-provider" && (
        <Modal title={`Remove provider ${dialog.name}`} onClose={() => setDialog(null)}>
          <ConfirmForm
            text="The provider and its stored key are deleted from Zorua."
            label="remove"
            body={{ action: "provider.remove", name: dialog.name }}
            onDone={(m) => {
              dirty.current = false;
              finished(m);
              if (view.kind === "provider" && view.name === dialog.name) go({ kind: "overview" });
            }}
            onCancel={() => setDialog(null)}
          />
        </Modal>
      )}
      {dialog?.kind === "unbind" && (
        <Modal title="Unbind directory" onClose={() => setDialog(null)}>
          <ConfirmForm text={`Stop switching automatically in ${dialog.dir}.`} label="unbind" body={{ action: "binding.remove", dir: dialog.dir }} onDone={finished} onCancel={() => setDialog(null)} />
        </Modal>
      )}
    </div>
  );
}

function NotFound({ what, onBack }: { what: string; onBack: () => void }) {
  return (
    <p className="rounded-md border border-line bg-panel px-4 py-3 text-sm text-dim">
      No {what}.{" "}
      <button type="button" onClick={onBack} className="text-accent underline">
        back to overview
      </button>
    </p>
  );
}
