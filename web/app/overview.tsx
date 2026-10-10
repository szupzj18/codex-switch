import type { Account, Binding, Check, Provider, ZoruaState } from "@/lib/types";
import { attention, DOT, type Item } from "./attention";
import { CheckBadge } from "./check";
import { Icon, type IconName } from "./icons";
import { actionBtn, card, countBadge, dangerBtn, rowActions, sectionTitle } from "./ui";
import { CopyButton, shellQuote } from "./copy";
import { barColor, peak, PLAN_STYLE, textColor, UsagePanel } from "./usage";
import type { View } from "./view";

function Panel({ title, icon, count, action, children }: { title: string; icon: IconName; count?: number; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="min-w-0">
      <h2 className={sectionTitle}>
        <Icon name={icon} className="size-4 text-dim" />
        {title}
        {count != null && <span className={countBadge}>{count}</span>}
        {action && <span className="ml-auto font-normal">{action}</span>}
      </h2>
      <div className={card}>{children}</div>
    </section>
  );
}

function Stat({ label, value, sub, tone = "text-fg", onClick, hint, children }: { label: string; value: React.ReactNode; sub?: React.ReactNode; tone?: string; onClick?: () => void; hint?: string; children?: React.ReactNode }) {
  const body = (
    <>
      <div className="text-[11px] font-medium uppercase tracking-wider text-dim">{label}</div>
      <div className={`mt-1.5 text-2xl font-semibold leading-none tracking-tight tabular-nums ${tone}`}>{value}</div>
      {children}
      {sub != null && <div className="mt-2 truncate text-xs text-dim">{sub}</div>}
    </>
  );
  if (!onClick) return <div className={`${card} p-4`}>{body}</div>;
  return (
    <button type="button" onClick={onClick} title={hint} className={`${card} block w-full p-4 text-left transition-colors hover:border-accent`}>
      {body}
    </button>
  );
}

/** The numbers that answer "is anything wrong" before any row is read; a tile that points at something opens it. */
function Summary({ data, checks, checking, items, onOpen, onCheckAll }: { data: ZoruaState; checks: Record<string, Check>; checking: Set<string>; items: Item[]; onOpen: (v: View) => void; onCheckAll: () => void }) {
  const signedIn = data.accounts.filter((a) => a.state !== "none").length;
  const signedOut = data.accounts.find((a) => a.state === "none");
  let top: { a: Account; p: number } | null = null;
  for (const a of data.accounts) {
    const p = peak(a);
    if (p != null && (!top || p > top.p)) top = { a, p };
  }
  const results = data.providers.map((p) => checks[p.name]).filter(Boolean);
  const failed = results.filter((c) => c.status === "fail").length;
  const warned = results.filter((c) => c.status === "warn").length;
  const badProvider = data.providers.find((p) => checks[p.name] && checks[p.name].status !== "ok");
  const worst = items[0]?.tone;
  const unchecked = data.providers.length > 0 && results.length === 0;
  return (
    <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
      <Stat
        label="Accounts"
        value={`${signedIn}/${data.accounts.length}`}
        sub={signedOut ? `${data.accounts.length - signedIn} not signed in` : "all signed in"}
        onClick={signedOut ? () => onOpen({ kind: "account", name: signedOut.name }) : undefined}
        hint={signedOut ? `Open ${signedOut.name}` : undefined}
      />
      <Stat
        label="Highest usage"
        value={top ? `${top.p}%` : "—"}
        tone={top ? (top.p >= 50 ? textColor(top.p) : "text-fg") : "text-dim"}
        sub={top ? top.a.name : "no usage data yet"}
        onClick={top ? () => onOpen({ kind: "account", name: top.a.name }) : undefined}
        hint={top ? `Open ${top.a.name}` : undefined}
      >
        {top && (
          <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-line" aria-hidden>
            <div className={`h-full rounded-full ${barColor(top.p)}`} style={{ width: `${top.p}%` }} />
          </div>
        )}
      </Stat>
      <Stat
        label="Providers"
        value={data.providers.length}
        tone={failed ? "text-danger" : warned ? "text-warn" : "text-fg"}
        sub={
          checking.size > 0
            ? "checking…"
            : unchecked
              ? "not checked · check all"
              : results.length === 0
                ? "none yet"
                : failed || warned
                  ? `${failed} failed · ${warned} warning`
                  : `${results.length} checked, all ok`
        }
        onClick={checking.size > 0 ? undefined : unchecked ? onCheckAll : badProvider ? () => onOpen({ kind: "provider", name: badProvider.name }) : undefined}
        hint={unchecked ? "Check every provider" : badProvider ? `Open ${badProvider.name}` : undefined}
      />
      <Stat
        label="Needs attention"
        value={items.length}
        tone={worst === "danger" ? "text-danger" : worst === "warn" ? "text-warn" : items.length ? "text-fg" : "text-accent"}
        sub={items.length ? items[0].text : "all clear"}
        onClick={items.length ? () => onOpen(items[0].to) : undefined}
        hint={items.length ? "Open the most urgent item" : undefined}
      />
    </div>
  );
}

const ITEM_BG: Record<Item["tone"], string> = {
  danger: "border-danger/30 bg-danger/10 hover:border-danger",
  warn: "border-warn/30 bg-warn/10 hover:border-warn",
  info: "border-line-strong bg-panel hover:border-accent",
};

function Attention({ items, onOpen }: { items: Item[]; onOpen: (v: View) => void }) {
  if (items.length === 0) {
    return (
      <p className="mb-6 flex items-center gap-2 text-xs text-dim">
        <Icon name="check" className="size-3.5 text-accent" />
        nothing needs attention
      </p>
    );
  }
  return (
    <section aria-label="Needs attention" className="mb-6">
      <h2 className={sectionTitle}>Needs attention</h2>
      <ul className="flex flex-wrap gap-2">
        {items.map((i) => (
          <li key={i.key}>
            <button type="button" onClick={() => onOpen(i.to)} className={`flex items-center gap-2 rounded-full border px-3 py-1.5 text-left text-xs transition-colors ${ITEM_BG[i.tone]}`}>
              <span className={`size-2 shrink-0 rounded-full ${DOT[i.tone]}`} aria-hidden />
              {i.text}
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}

const AGENT_TONE: Record<Account["agent"], string> = { codex: "bg-info/15 text-info", claude: "bg-violet/15 text-violet" };
const ROW = "row-pad grid grid-cols-1 gap-4 border-b border-line px-4 transition-colors last:border-b-0 hover:bg-panel-2 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.3fr)]";

function AccountRow({ a, onOpen, onLogin, onRemove }: { a: Account; onOpen: () => void; onLogin: () => void; onRemove: () => void }) {
  return (
    <li className={ROW}>
      <div className="flex min-w-0 items-start gap-3">
        <span className={`grid size-9 shrink-0 place-items-center rounded-xl text-sm font-semibold uppercase ${AGENT_TONE[a.agent]}`} aria-hidden>
          {a.name[0]}
        </span>
        <div className="min-w-0">
          <div className="flex flex-wrap items-baseline gap-x-2">
            <button type="button" onClick={onOpen} className="font-semibold hover:text-accent">
              {a.name}
            </button>
            {a.plan && <span className={`rounded-full bg-line px-2 py-px text-[11px] font-medium ${PLAN_STYLE[a.plan] ?? "text-fg"}`}>{a.plan}</span>}
          </div>
          <div className="truncate text-xs text-dim" title={a.email ?? undefined}>
            {a.email ?? "—"}
          </div>
          <div className="truncate font-mono text-[11px] text-dim" title={a.home}>
            {a.home}
          </div>
        </div>
      </div>
      <UsagePanel a={a} />
      <div className={rowActions}>
        <button type="button" onClick={onLogin} className={actionBtn}>
          sign in
        </button>
        <CopyButton variant="action" text="copy command" label={`copy: zorua use ${a.name}`} get={async () => `zorua use ${a.name}`} />
        {a.name !== "default" && (
          <button type="button" onClick={onRemove} className={dangerBtn}>
            remove
          </button>
        )}
      </div>
    </li>
  );
}

function ProviderRow({ p, check, checking, onOpen, onCheck, onRemove }: { p: Provider; check?: Check; checking: boolean; onOpen: () => void; onCheck: () => void; onRemove: () => void }) {
  const models = Object.keys(p.models);
  return (
    <li className={ROW}>
      <div className="min-w-0">
        <button type="button" onClick={onOpen} className="font-semibold hover:text-accent">
          {p.name}
        </button>
        <span className="ml-2 rounded-full bg-line px-2 py-px text-[11px] text-dim">{p.agent}</span>
        <div className="truncate font-mono text-xs text-dim">{p.endpoint}</div>
      </div>
      <div className="min-w-0 text-xs text-dim">
        <CheckBadge check={check} checking={checking} onCheck={onCheck} />
        <div className="mt-1.5">
          {models.length === 0 ? "no model catalog" : `${models.length} model${models.length === 1 ? "" : "s"}: ${models.slice(0, 4).join(", ")}${models.length > 4 ? " …" : ""}`}
        </div>
      </div>
      <div className={rowActions}>
        <button type="button" onClick={onOpen} className={actionBtn}>
          view &amp; edit
        </button>
        <CopyButton variant="action" text="copy command" label={`copy: zorua use ${p.name}`} get={async () => `zorua use ${p.name}`} />
        <button type="button" onClick={onRemove} className={dangerBtn}>
          remove
        </button>
      </div>
    </li>
  );
}

function BindingRow({ b, onRemove }: { b: Binding; onRemove: () => void }) {
  return (
    <li className="row-pad flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-line px-4 transition-colors last:border-b-0 hover:bg-panel-2">
      <span className="min-w-0 flex-1 truncate font-mono text-[13px]" title={b.dir}>
        {b.dir}
      </span>
      <span className="rounded-full bg-accent/10 px-2.5 py-0.5 text-xs font-medium text-accent">→ {b.name}</span>
      <CopyButton variant="action" text="copy command" label={`copy: zorua bind ${b.name} in ${b.dir}`} get={async () => `cd ${shellQuote(b.dir)} && zorua bind ${b.name}`} />
      <button type="button" onClick={onRemove} className={dangerBtn}>
        unbind
      </button>
    </li>
  );
}

const empty = (text: string) => <li className="px-4 py-6 text-center text-xs text-dim">{text}</li>;

/** Grey placeholders with the overview's shape, shown until the first read finishes. */
export function OverviewSkeleton() {
  const block = "squircle animate-shimmer rounded-2xl border border-line bg-panel";
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className={`${block} h-[104px]`} />
        ))}
      </div>
      <div className="grid gap-x-6 gap-y-8 xl:grid-cols-2">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className={`${block} h-56`} />
        ))}
      </div>
    </div>
  );
}

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
  const items = attention(data, checks);
  return (
    <>
      <Summary data={data} checks={checks} checking={checking} items={items} onOpen={onOpen} onCheckAll={onCheckAll} />
      <Attention items={items} onOpen={onOpen} />
      <div className="grid gap-x-6 gap-y-8 xl:grid-cols-2">
        <Panel title="Codex" icon="user" count={codex.length}>
          <ul>{codex.length ? codex : empty("no accounts")}</ul>
        </Panel>
        <Panel title="Claude Code" icon="user" count={claude.length}>
          <ul>{claude.length ? claude : empty("no accounts")}</ul>
        </Panel>
        <Panel
          title="Providers"
          icon="plug"
          count={providers.length}
          action={
            providers.length > 0 && (
              <button type="button" onClick={onCheckAll} disabled={checking.size > 0} className={actionBtn}>
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
        <Panel title="Directory bindings" icon="folder" count={data.bindings.length}>
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
