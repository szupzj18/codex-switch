import type { Account, Binding } from "@/lib/types";
import { CopyButton, shellQuote } from "./copy";
import { actionBtn, actionRow, dangerBtn } from "./ui";
import { ago, Bar, PLAN_STYLE, usageNote } from "./usage";

function Fact({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-[7rem_minmax(0,1fr)] gap-2 border-b border-line px-4 py-2 text-sm last:border-b-0">
      <span className="text-xs text-dim">{label}</span>
      <span className="min-w-0 break-all">{children}</span>
    </div>
  );
}

export function AccountView({ a, bindings, onLogin, onRemove, onUnbind }: { a: Account; bindings: Binding[]; onLogin: () => void; onRemove: () => void; onUnbind: (dir: string) => void }) {
  const ws = a.usage.windows;
  const note = usageNote(a);
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <section>
        <h2 className="mb-3 text-sm before:mr-2 before:text-accent before:content-['#']">Account</h2>
        <div className="overflow-hidden rounded-[10px] border border-line bg-panel">
          <Fact label="name">
            <b className="text-accent">{a.name}</b> <span className="text-xs text-dim">{a.agent === "codex" ? "Codex CLI" : "Claude Code"}</span>
          </Fact>
          <Fact label="plan">{a.plan ? <span className={PLAN_STYLE[a.plan] ?? ""}>{a.plan}</span> : "—"}</Fact>
          <Fact label="email">{a.email ?? "—"}</Fact>
          <Fact label="sign-in">{a.state === "ok" ? "signed in" : a.state === "none" ? "not signed in" : a.state === "apikey" ? "API key login" : a.state}</Fact>
          {a.until && <Fact label="subscription">until {a.until}</Fact>}
          <Fact label={a.agent === "codex" ? "CODEX_HOME" : "CLAUDE_CONFIG_DIR"}>
            <code>{a.home}</code>
          </Fact>
        </div>
        <div className={actionRow}>
          <button type="button" onClick={onLogin} className={actionBtn}>
            sign in again
          </button>
          <CopyButton variant="action" text="copy command" label={`copy: zorua use ${a.name}`} get={async () => `zorua use ${a.name}`} />
          {a.name !== "default" && (
            <button type="button" onClick={onRemove} className={dangerBtn}>
              remove
            </button>
          )}
        </div>
      </section>
      <section>
        <h2 className="mb-3 text-sm before:mr-2 before:text-accent before:content-['#']">Usage</h2>
        <div className="rounded-[10px] border border-line bg-panel p-4">
          {ws.length > 0 ? (
            <div className="grid grid-cols-2 gap-6">
              {ws.map((w, i) => (
                <Bar key={i} w={w} />
              ))}
            </div>
          ) : (
            <div className="text-xs text-dim">{note}</div>
          )}
          {ws.length > 0 && a.usage.age_seconds != null && <div className="mt-3 text-[11px] text-dim">from its last session, {ago(a.usage.age_seconds)}</div>}
          {ws.length > 0 && note && <div className="mt-2 text-[11px] text-danger">{note}</div>}
        </div>
        <h2 className="mb-3 mt-6 text-sm before:mr-2 before:text-accent before:content-['#']">Bound directories</h2>
        <div className="overflow-hidden rounded-[10px] border border-line bg-panel">
          {bindings.length ? (
            bindings.map((b) => (
              <div key={b.dir} className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-line px-4 py-3 text-sm last:border-b-0">
                <span className="min-w-0 flex-1 truncate" title={b.dir}>
                  {b.dir}
                </span>
                <CopyButton variant="action" text="copy command" label={`copy: zorua bind ${b.name} in ${b.dir}`} get={async () => `cd ${shellQuote(b.dir)} && zorua bind ${b.name}`} />
                <button type="button" onClick={() => onUnbind(b.dir)} className={dangerBtn}>
                  unbind
                </button>
              </div>
            ))
          ) : (
            <div className="px-4 py-3 text-xs text-dim">none — `zorua bind {a.name}` inside a directory binds it</div>
          )}
        </div>
      </section>
    </div>
  );
}
