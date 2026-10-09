import type { ZoruaState } from "@/lib/types";
import { ThemeSwitch } from "./theme";
import { peak, textColor } from "./usage";
import { sameView, type View } from "./view";

function Item({ active, onClick, children, right }: { active: boolean; onClick: () => void; children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <li>
      <button
        type="button"
        onClick={onClick}
        aria-current={active ? "page" : undefined}
        className={`flex w-full items-baseline justify-between gap-2 border-l-2 px-3 py-1.5 text-left text-sm ${active ? "border-accent bg-accent/10 text-accent" : "border-transparent text-fg hover:bg-line/50"}`}
      >
        <span className="min-w-0 truncate">{children}</span>
        {right}
      </button>
    </li>
  );
}

function Group({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mt-4">
      <div className="px-3 pb-1 text-[10px] uppercase tracking-widest text-dim">{title}</div>
      <ul>{children}</ul>
    </div>
  );
}

export function Sidebar({ data, view, onGo }: { data: ZoruaState | undefined; view: View; onGo: (v: View) => void }) {
  const at = (v: View) => sameView(view, v);
  const accounts = (agent: "codex" | "claude") =>
    data?.accounts
      .filter((a) => a.agent === agent)
      .map((a) => {
        const p = peak(a);
        return (
          <Item
            key={a.name}
            active={at({ kind: "account", name: a.name })}
            onClick={() => onGo({ kind: "account", name: a.name })}
            right={p != null ? <span className={`text-[11px] tabular-nums ${textColor(p)}`}>{p}%</span> : a.state === "none" ? <span className="text-[11px] text-dim">–</span> : undefined}
          >
            {a.name}
          </Item>
        );
      });
  return (
    <nav aria-label="Zorua" className="rounded-[10px] border border-line bg-panel py-3 lg:sticky lg:top-4 lg:self-start lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto">
      <div className="px-3">
        <button type="button" onClick={() => onGo({ kind: "overview" })} className="flex items-center gap-2 text-left">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/icon.svg" width={28} height={28} alt="" className="rounded-lg" />
          <span className="font-bold">zorua</span>
          {data && <span className="text-[11px] text-dim">{data.version}</span>}
        </button>
      </div>
      <ul className="mt-3">
        <Item active={view.kind === "overview"} onClick={() => onGo({ kind: "overview" })}>
          Overview
        </Item>
      </ul>
      {data && (
        <>
          <Group title="Codex">{accounts("codex")}</Group>
          <Group title="Claude Code">{accounts("claude")}</Group>
          <Group title="Providers">
            {data.providers.map((p) => (
              <Item key={p.name} active={at({ kind: "provider", name: p.name })} onClick={() => onGo({ kind: "provider", name: p.name })} right={<span className="text-[10px] text-dim">{p.agent}</span>}>
                {p.name}
              </Item>
            ))}
          </Group>
        </>
      )}
      <ThemeSwitch />
    </nav>
  );
}
