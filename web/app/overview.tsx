import type { Account, Binding, Check, Provider, ZoruaState } from "@/lib/types";
import { attention, DOT, type Item } from "./attention";
import { CheckBadge } from "./check";
import { CopyButton, shellQuote } from "./copy";
import { ago, Bar, PLAN_STYLE, usageNote } from "./usage";
import type { View } from "./view";

function Panel({ title, count, action, children }: { title: string; count?: number; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="min-w-0">
      <h2 className="mb-3 flex items-baseline text-sm before:mr-2 before:text-accent before:content-['#']">
        {title}
        {count != null && <span className="ml-2 text-xs text-dim">{count}</span>}
        {action && <span className="ml-auto text-[11px] font-normal">{action}</span>}
      </h2>
      <div className="overflow-hidden rounded-[10px] border border-line bg-panel">{children}</div>
    </section>
  );
}

const linkBtn = "text-dim underline hover:text-accent";

function Attention({ items, onOpen }: { items: Item[]; onOpen: (v: View) => void }) {
  if (items.length === 0) return <p className="mb-6 text-xs text-dim">✓ nothing needs attention</p>;
  return (
    <section aria-label="Needs attention" className="mb-6">
      <h2 className="mb-2 text-sm before:mr-2 before:text-accent before:content-['#']">Needs attention</h2>
      <ul className="flex flex-wrap gap-2">
        {items.map((i) => (
          <li key={i.key}>
            <button type="button" onClick={() => onOpen(i.to)} className="flex items-center gap-2 rounded-md border border-line bg-panel px-3 py-1.5 text-left text-xs hover:border-accent">
              <span className={`size-2 shrink-0 rounded-full ${DOT[i.tone]}`} aria-hidden />
              {i.text}
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}

function AccountRow({ a, onOpen, onLogin, onRemove }: { a: Account; onOpen: () => void; onLogin: () => void; onRemove: () => void }) {
  const ws = a.usage.windows;
  const note = usageNote(a);
  return (
    <li className="grid grid-cols-1 gap-3 border-b border-line px-4 py-3 last:border-b-0 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.3fr)]">
      <div className="min-w-0">
        <div className="flex flex-wrap items-baseline gap-x-2">
          <button type="button" onClick={onOpen} className="font-bold text-accent hover:underline">
            {a.name}
          </button>
          {a.plan && <span className={`text-xs ${PLAN_STYLE[a.plan] ?? "text-fg"}`}>{a.plan}</span>}
        </div>
        <div className="truncate text-xs text-dim" title={a.email ?? undefined}>
          {a.email ?? "—"}
        </div>
        <div className="truncate text-[11px] text-dim/70" title={a.home}>
          {a.home}
        </div>
        <div className="mt-2 flex gap-3 text-[11px]">
          <button type="button" onClick={onLogin} className={linkBtn}>
            sign in
          </button>
          <CopyButton variant="link" text="copy command" label={`copy: zorua use ${a.name}`} get={async () => `zorua use ${a.name}`} />
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
        {ws.length > 0 && a.usage.age_seconds != null && <div className="mt-2 text-[11px] text-dim">from its last session, {ago(a.usage.age_seconds)}</div>}
        {ws.length > 0 && note && <div className="mt-2 text-[11px] text-danger">{note}</div>}
      </div>
    </li>
  );
}

function ProviderRow({ p, check, checking, onOpen, onCheck, onRemove }: { p: Provider; check?: Check; checking: boolean; onOpen: () => void; onCheck: () => void; onRemove: () => void }) {
  const models = Object.keys(p.models);
  return (
    <li className="grid grid-cols-1 gap-1 border-b border-line px-4 py-3 last:border-b-0 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.3fr)]">
      <div className="min-w-0">
        <button type="button" onClick={onOpen} className="font-bold text-accent hover:underline">
          {p.name}
        </button>
        <span className="ml-2 text-[11px] text-dim">{p.agent}</span>
        <div className="truncate text-xs text-dim">{p.endpoint}</div>
        <div className="mt-1 flex gap-3 text-[11px]">
          <button type="button" onClick={onOpen} className={linkBtn}>
            view &amp; edit
          </button>
          <CopyButton variant="link" text="copy command" label={`copy: zorua use ${p.name}`} get={async () => `zorua use ${p.name}`} />
          <button type="button" onClick={onRemove} className="text-dim underline hover:text-danger">
            remove
          </button>
        </div>
      </div>
      <div className="min-w-0 text-xs text-dim">
        <CheckBadge check={check} checking={checking} onCheck={onCheck} />
        <div className="mt-1">
          {models.length === 0 ? "no model catalog" : `${models.length} model${models.length === 1 ? "" : "s"}: ${models.slice(0, 4).join(", ")}${models.length > 4 ? " …" : ""}`}
        </div>
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
      <span className="text-[11px]">
        <CopyButton variant="link" text="copy command" label={`copy: zorua bind ${b.name} in ${b.dir}`} get={async () => `cd ${shellQuote(b.dir)} && zorua bind ${b.name}`} />
      </span>
      <button type="button" onClick={onRemove} className="text-[11px] text-dim underline hover:text-danger">
        unbind
      </button>
    </li>
  );
}

const empty = (text: string) => <li className="px-4 py-3 text-xs text-dim">{text}</li>;

export function Overview({
  data,
  checks,
  checking,
  onOpen,
  onLogin,
  onCheck,
  onCheckAll,
  onRemoveAccount,
  onRemoveProvider,
  onUnbind,
}: {
  data: ZoruaState;
  checks: Record<string, Check>;
  checking: Set<string>;
  onOpen: (v: View) => void;
  onLogin: (a: Account) => void;
  onCheck: (name: string) => void;
  onCheckAll: () => void;
  onRemoveAccount: (a: Account) => void;
  onRemoveProvider: (name: string) => void;
  onUnbind: (dir: string) => void;
}) {
  const accounts = (agent: Account["agent"]) =>
    data.accounts
      .filter((a) => a.agent === agent)
      .map((a) => <AccountRow key={a.name} a={a} onOpen={() => onOpen({ kind: "account", name: a.name })} onLogin={() => onLogin(a)} onRemove={() => onRemoveAccount(a)} />);
  const codex = accounts("codex");
  const claude = accounts("claude");
  const providers = [...data.providers].sort((x, y) => x.agent.localeCompare(y.agent) || x.name.localeCompare(y.name));
  return (
    <>
      <Attention items={attention(data, checks)} onOpen={onOpen} />
      <div className="grid gap-x-6 gap-y-8 xl:grid-cols-2">
        <Panel title="Codex" count={codex.length}>
          <ul>{codex.length ? codex : empty("no accounts")}</ul>
        </Panel>
        <Panel title="Claude Code" count={claude.length}>
          <ul>{claude.length ? claude : empty("no accounts")}</ul>
        </Panel>
        <Panel
          title="Providers"
          count={providers.length}
          action={
            providers.length > 0 && (
              <button type="button" onClick={onCheckAll} disabled={checking.size > 0} className="text-dim underline hover:text-accent disabled:opacity-50">
                {checking.size > 0 ? "checking…" : "check all"}
              </button>
            )
          }
        >
          <ul>
            {providers.length
              ? providers.map((p) => (
                  <ProviderRow
                    key={`${p.agent}:${p.name}`}
                    p={p}
                    check={checks[p.name]}
                    checking={checking.has(p.name)}
                    onOpen={() => onOpen({ kind: "provider", name: p.name })}
                    onCheck={() => onCheck(p.name)}
                    onRemove={() => onRemoveProvider(p.name)}
                  />
                ))
              : empty("no providers")}
          </ul>
        </Panel>
        <Panel title="Directory bindings" count={data.bindings.length}>
          <ul>
            {data.bindings.length
              ? data.bindings.map((b) => <BindingRow key={`${b.dir}:${b.name}`} b={b} onRemove={() => onUnbind(b.dir)} />)
              : empty("no bindings — a bound directory switches to its account when you cd into it")}
          </ul>
        </Panel>
      </div>
    </>
  );
}
