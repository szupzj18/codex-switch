import type { Account, Binding, Provider, ZoruaState } from "@/lib/types";
import { ago, Bar, PLAN_STYLE, usageNote } from "./usage";
import type { View } from "./view";

function Panel({ title, count, children }: { title: string; count?: number; children: React.ReactNode }) {
  return (
    <section className="min-w-0">
      <h2 className="mb-3 text-sm before:mr-2 before:text-accent before:content-['#']">
        {title}
        {count != null && <span className="ml-2 text-xs text-dim">{count}</span>}
      </h2>
      <div className="overflow-hidden rounded-[10px] border border-line bg-panel">{children}</div>
    </section>
  );
}

const linkBtn = "text-dim underline hover:text-accent";

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

function ProviderRow({ p, onOpen, onRemove }: { p: Provider; onOpen: () => void; onRemove: () => void }) {
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
          <button type="button" onClick={onRemove} className="text-dim underline hover:text-danger">
            remove
          </button>
        </div>
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

const empty = (text: string) => <li className="px-4 py-3 text-xs text-dim">{text}</li>;

export function Overview({
  data,
  onOpen,
  onLogin,
  onRemoveAccount,
  onRemoveProvider,
  onUnbind,
}: {
  data: ZoruaState;
  onOpen: (v: View) => void;
  onLogin: (a: Account) => void;
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
    <div className="grid gap-x-6 gap-y-8 xl:grid-cols-2">
      <Panel title="Codex" count={codex.length}>
        <ul>{codex.length ? codex : empty("no accounts")}</ul>
      </Panel>
      <Panel title="Claude Code" count={claude.length}>
        <ul>{claude.length ? claude : empty("no accounts")}</ul>
      </Panel>
      <Panel title="Providers" count={providers.length}>
        <ul>
          {providers.length
            ? providers.map((p) => <ProviderRow key={`${p.agent}:${p.name}`} p={p} onOpen={() => onOpen({ kind: "provider", name: p.name })} onRemove={() => onRemoveProvider(p.name)} />)
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
  );
}
