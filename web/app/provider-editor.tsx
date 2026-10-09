"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ProviderDoc } from "@/lib/types";
import { act } from "./manage";

const field =
  "w-full rounded-md border border-line bg-bg px-2 py-1 text-xs text-fg outline-none placeholder:text-dim/60 focus:border-accent";
const primary = "rounded-md bg-accent px-4 py-1.5 text-xs font-bold text-on-accent disabled:opacity-40";
const ghost = "rounded-md border border-line px-3 py-1.5 text-xs text-dim hover:text-fg disabled:opacity-40";

type Row = { id: number; k: string; v: string };
type Tab = "main" | "models" | "json";

/** Same rule as zorua_providers.is_secret. */
const isSecret = (v: string) => /TOKEN|KEY|SECRET|PASSWORD/.test(v.toUpperCase()) && !v.toUpperCase().endsWith("_TOKENS");

let nextId = 1;
const rows = (o: Record<string, string>): Row[] => Object.entries(o).map(([k, v]) => ({ id: nextId++, k, v }));

async function fetchDoc(name: string, reveal: boolean): Promise<ProviderDoc> {
  const r = await fetch("/api/provider", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Zorua-Web": "1" },
    body: JSON.stringify({ name, reveal }),
    cache: "no-store",
  });
  const body = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(body.error ?? `HTTP ${r.status}`);
  return body.doc as ProviderDoc;
}

/** A one-line-looking input that grows to show a long value (a key is ~50 characters) in full. */
function Value({ label, value, onChange, className = "" }: { label: string; value: string; onChange: (v: string) => void; className?: string }) {
  const ref = useRef<HTMLTextAreaElement>(null);
  useEffect(() => {
    const t = ref.current;
    if (!t) return;
    t.style.height = "auto";
    t.style.height = `${t.scrollHeight + 2}px`;
  }, [value]);
  return (
    <textarea
      ref={ref}
      aria-label={label}
      rows={1}
      className={`${field} resize-none break-all leading-snug ${className}`}
      value={value}
      onChange={(e) => onChange(e.target.value.replace(/[\r\n]/g, ""))}
      spellCheck={false}
      autoComplete="off"
    />
  );
}

function Table({
  items,
  onChange,
  secret,
  keyLabel,
  valueLabel,
  addLabel,
}: {
  items: Row[];
  onChange: (r: Row[]) => void;
  secret?: (k: string) => boolean;
  keyLabel: string;
  valueLabel: string;
  addLabel: string;
}) {
  const set = (id: number, patch: Partial<Row>) => onChange(items.map((r) => (r.id === id ? { ...r, ...patch } : r)));
  return (
    <div>
      <div className="grid grid-cols-[minmax(9rem,20rem)_minmax(0,1fr)_1.5rem] items-start gap-x-2 gap-y-1.5">
        {items.map((r) => (
          <div key={r.id} className="contents">
            <input aria-label={keyLabel} className={field} value={r.k} onChange={(e) => set(r.id, { k: e.target.value })} spellCheck={false} />
            <Value label={valueLabel} className={secret?.(r.k) ? "text-warn" : ""} value={r.v} onChange={(v) => set(r.id, { v })} />
            <button type="button" aria-label={`delete ${r.k || "row"}`} className="py-1 text-dim hover:text-danger" onClick={() => onChange(items.filter((x) => x.id !== r.id))}>
              ×
            </button>
          </div>
        ))}
      </div>
      <button type="button" className="mt-3 text-xs text-dim underline hover:text-accent" onClick={() => onChange([...items, { id: nextId++, k: "", v: "" }])}>
        + {addLabel}
      </button>
    </div>
  );
}

function Labeled({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="grid gap-1 text-xs text-dim sm:grid-cols-[12rem_minmax(0,1fr)] sm:gap-3">
      <span className="py-1">{label}</span>
      <span>
        {children}
        {hint && <span className="mt-1 block text-[11px] text-dim/70">{hint}</span>}
      </span>
    </label>
  );
}

/** One provider as a page: every env variable, the key, the model catalog and the raw JSON. */
export function ProviderPage({
  name,
  endpoint,
  onSaved,
  onDirty,
  onRemove,
}: {
  name: string;
  endpoint: string;
  onSaved: (message: string) => void;
  onDirty: (dirty: boolean) => void;
  onRemove: () => void;
}) {
  const [base, setBase] = useState<ProviderDoc | null>(null); // as stored (secrets masked)
  const [open, setOpen] = useState<ProviderDoc | null>(null); // same, secrets revealed
  const [revealed, setRevealed] = useState(false);
  const [env, setEnv] = useState<Row[]>([]);
  const [cat, setCat] = useState<Row[]>([]);
  const [codex, setCodex] = useState({ base_url: "", key: "", model: "", wire_api: "responses" });
  const [tab, setTab] = useState<Tab>("main");
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const apply = useCallback((d: ProviderDoc) => {
    setCat(rows(d.models));
    if (d.agent === "claude") setEnv(rows(d.env));
    else setCodex({ base_url: d.base_url, key: d.key, model: d.model, wire_api: d.wire_api });
  }, []);

  useEffect(() => {
    let stop = false;
    fetchDoc(name, false)
      .then((d) => {
        if (stop) return;
        setBase(d);
        apply(d);
      })
      .catch((e) => !stop && setLoadError(e instanceof Error ? e.message : String(e)));
    return () => {
      stop = true;
    };
  }, [name, apply]);

  /** Swap masked secrets for the real values (and back) wherever the user has not edited them. */
  const toggleReveal = async () => {
    if (!base) return;
    setError(null);
    try {
      const full = open ?? (await fetchDoc(name, true));
      setOpen(full);
      const [from, to] = revealed ? [full, base] : [base, full];
      if (base.agent === "claude" && from.agent === "claude" && to.agent === "claude") {
        setEnv((cur) => cur.map((r) => (isSecret(r.k) && r.v === from.env[r.k] ? { ...r, v: to.env[r.k] ?? r.v } : r)));
      } else if (base.agent === "codex" && from.agent === "codex" && to.agent === "codex") {
        setCodex((c) => (c.key === from.key ? { ...c, key: to.key } : c));
      }
      setRevealed(!revealed);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const toMap = (items: Row[], what: string): Record<string, string> => {
    const out: Record<string, string> = {};
    for (const r of items) {
      if (!r.k && !r.v) continue;
      if (!r.k) throw new Error(`${what}: a row has a value but no name`);
      if (r.k in out) throw new Error(`${what}: '${r.k}' appears twice`);
      out[r.k] = r.v;
    }
    return out;
  };

  const built = useMemo((): { doc: ProviderDoc | null; problem: string | null } => {
    if (!base) return { doc: null, problem: null };
    try {
      const models = toMap(cat, "models");
      if (base.agent === "claude") return { doc: { agent: "claude", env: toMap(env, "env"), models }, problem: null };
      return { doc: { agent: "codex", ...codex, models }, problem: null };
    } catch (e) {
      return { doc: null, problem: e instanceof Error ? e.message : String(e) };
    }
  }, [base, cat, env, codex]);

  // Compare against what is on screen as stored: masked while hidden, real values once revealed.
  const reference = revealed ? open : base;
  const dirty = built.doc !== null && reference !== null && JSON.stringify(built.doc) !== JSON.stringify(reference);

  useEffect(() => {
    onDirty(dirty);
    return () => onDirty(false);
  }, [dirty, onDirty]);

  const save = async () => {
    if (!built.doc) return;
    setBusy(true);
    setError(null);
    try {
      onSaved((await act({ action: "provider.save", name, doc: built.doc })).message);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setBusy(false);
    }
  };

  if (loadError) return <p className="rounded-md border border-danger/40 bg-danger/10 px-3 py-2 text-xs text-danger">{loadError}</p>;
  if (!base) return <p className="text-xs text-dim">reading {name}…</p>;

  const claude = base.agent === "claude";
  const tabs: [Tab, string][] = [
    ["main", claude ? `Environment (${env.length})` : "Connection"],
    ["models", `Models (${cat.length})`],
    ["json", "JSON"],
  ];
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        save();
      }}
      autoComplete="off"
    >
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="text-sm text-dim">
          {claude ? "Claude Code" : "Codex"} provider · <span className="text-fg">{endpoint}</span>
        </span>
        <span className="ml-auto flex gap-4 text-xs">
          <button type="button" className="text-dim underline hover:text-accent" onClick={toggleReveal}>
            {revealed ? "hide keys" : "show keys"}
          </button>
          <button type="button" className="text-dim underline hover:text-danger" onClick={onRemove}>
            remove provider
          </button>
        </span>
      </div>
      <p className="mt-1 text-[11px] text-dim">
        {claude ? "These variables are what `claude` runs with while this provider is active." : "Codex gets this endpoint, key and model through -c overrides."} Keys are masked until{" "}
        <b className="text-fg">show keys</b>.
      </p>

      <div role="tablist" className="mt-4 flex gap-1 border-b border-line">
        {tabs.map(([id, label]) => (
          <button
            key={id}
            type="button"
            role="tab"
            aria-selected={tab === id}
            onClick={() => setTab(id)}
            className={`-mb-px border-b-2 px-3 py-2 text-xs ${tab === id ? "border-accent text-accent" : "border-transparent text-dim hover:text-fg"}`}
          >
            {label}
          </button>
        ))}
      </div>

      <div className="mt-4 rounded-[10px] border border-line bg-panel p-4">
        {tab === "main" &&
          (claude ? (
            <>
              <p className="mb-3 text-[11px] text-dim/70">ANTHROPIC_BASE_URL and a key (ANTHROPIC_AUTH_TOKEN or ANTHROPIC_API_KEY) are required. Highlighted values are secrets.</p>
              <Table items={env} onChange={setEnv} secret={isSecret} keyLabel="variable" valueLabel="value" addLabel="add variable" />
            </>
          ) : (
            <div className="grid gap-3">
              <Labeled label="base URL">
                <Value label="base URL" value={codex.base_url} onChange={(v) => setCodex({ ...codex, base_url: v })} />
              </Labeled>
              <Labeled label="key">
                <Value label="key" className="text-warn" value={codex.key} onChange={(v) => setCodex({ ...codex, key: v })} />
              </Labeled>
              <Labeled label="model" hint="what Codex sends when no model is picked">
                <Value label="model" value={codex.model} onChange={(v) => setCodex({ ...codex, model: v })} />
              </Labeled>
              <Labeled label="wire API">
                <select className={field} value={codex.wire_api} onChange={(e) => setCodex({ ...codex, wire_api: e.target.value })}>
                  <option value="responses">responses</option>
                  <option value="chat">chat</option>
                </select>
              </Labeled>
            </div>
          ))}
        {tab === "models" && (
          <>
            <p className="mb-3 text-[11px] text-dim/70">alias → full model id. `zorua use {name}:&lt;alias&gt;` picks one for a shell.</p>
            <Table items={cat} onChange={setCat} keyLabel="alias" valueLabel="model id" addLabel="add model" />
          </>
        )}
        {tab === "json" && (
          <pre className="max-h-[60vh] overflow-auto whitespace-pre-wrap break-all text-[11px] text-dim">{built.doc ? JSON.stringify(built.doc, null, 2) : built.problem}</pre>
        )}
      </div>

      {(error || built.problem) && <p className="mt-3 rounded-md border border-danger/40 bg-danger/10 px-3 py-2 text-xs text-danger">{error ?? built.problem}</p>}

      <div className="sticky bottom-0 mt-4 flex flex-wrap items-center gap-3 border-t border-line bg-bg/95 py-3 backdrop-blur">
        <span className="text-[11px] text-dim/70">
          {dirty ? <span className="text-warn">unsaved changes</span> : "saved"} · saving keeps the previous file as providers.json.bak; shells that already launched claude keep their old settings
        </span>
        <span className="ml-auto flex gap-2">
          <button type="button" className={ghost} disabled={!dirty} onClick={() => reference && apply(reference)}>
            discard
          </button>
          <button type="submit" className={primary} disabled={busy || !dirty || !built.doc}>
            {busy ? "saving…" : "save"}
          </button>
        </span>
      </div>
    </form>
  );
}
