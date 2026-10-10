"use client";

import { useEffect, useRef } from "react";
import type { ZoruaState } from "@/lib/types";
import { DOT, type Item as Attn } from "./attention";
import { Icon, type IconName } from "./icons";
import { ThemeSwitch } from "./theme";
import { countBadge } from "./ui";
import { peak, textColor } from "./usage";
import { sameView, type View } from "./view";

function Item({ active, onClick, children, right, tone, icon }: { active: boolean; onClick: () => void; children: React.ReactNode; right?: React.ReactNode; tone?: Attn["tone"]; icon?: IconName }) {
  return (
    <li>
      <button
        type="button"
        onClick={onClick}
        aria-current={active ? "page" : undefined}
        className={`flex w-full items-center justify-between gap-2 rounded-lg px-2.5 py-1.5 text-left text-[13px] transition-colors ${active ? "bg-accent/10 font-medium text-accent" : "text-fg hover:bg-line/60"}`}
      >
        <span className="flex min-w-0 items-center gap-2">
          {icon && <Icon name={icon} className="size-4 text-dim" />}
          <span className="truncate">{children}</span>
          {tone && <span className={`size-1.5 shrink-0 rounded-full ${DOT[tone]}`} role="img" aria-label="needs attention" />}
        </span>
        {right}
      </button>
    </li>
  );
}

function Group({ title, count, children }: { title: string; count: number; children: React.ReactNode }) {
  return (
    <div className="mt-5">
      <div className="flex items-center justify-between px-5 pb-1.5 text-xs font-medium uppercase tracking-wider text-dim">
        {title}
        <span className={countBadge}>{count}</span>
      </div>
      <ul className="px-2">{children}</ul>
    </div>
  );
}

export function Sidebar({
  data,
  view,
  items,
  onGo,
  onSearch,
  open,
  onClose,
}: {
  data: ZoruaState | undefined;
  view: View;
  items: Attn[];
  onGo: (v: View) => void;
  onSearch: () => void;
  /** Below `lg` the sidebar is a drawer that is only mounted while open. */
  open: boolean;
  onClose: () => void;
}) {
  const at = (v: View) => sameView(view, v);
  // As a drawer (below lg) it behaves like a dialog: focus moves into it, Esc closes it, and the page behind
  // is inert (dashboard.tsx), so Tab cannot wander off into content that is covered.
  const closeBtn = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (open) closeBtn.current?.focus();
  }, [open]);
  // The worst item per entry (items arrive worst first).
  const tones = new Map<string, Attn["tone"]>();
  for (const i of items) if (!tones.has(i.key)) tones.set(i.key, i.tone);
  const accounts = (agent: "codex" | "claude") => data?.accounts.filter((a) => a.agent === agent) ?? [];
  const accountItems = (agent: "codex" | "claude") =>
    accounts(agent).map((a) => {
      const p = peak(a);
      return (
        <Item
          key={a.name}
          tone={tones.get(`a:${a.name}`)}
          active={at({ kind: "account", name: a.name })}
          onClick={() => onGo({ kind: "account", name: a.name })}
          right={p != null ? <span className={`text-xs font-medium tabular-nums ${textColor(p)}`}>{p}%</span> : a.state === "none" ? <span className="text-xs text-dim">–</span> : undefined}
        >
          {a.name}
        </Item>
      );
    });
  return (
    <>
      {open && <div className="fixed inset-0 z-30 bg-black/60 backdrop-blur-sm lg:hidden" onClick={onClose} aria-hidden />}
      <nav
        aria-label="Zorua"
        onKeyDown={(e) => {
          if (open && e.key === "Escape") onClose();
        }}
        className={`${open ? "fixed inset-y-0 left-0 z-40 w-72 animate-slide-in overflow-y-auto border-r border-line-strong" : "hidden"} bg-panel pb-3 pt-4 lg:sticky lg:top-4 lg:z-auto lg:block lg:max-h-[calc(100vh-2rem)] lg:w-auto lg:animate-none lg:self-start lg:overflow-y-auto lg:squircle lg:rounded-2xl lg:border lg:border-line lg:shadow-card`}
      >
        <div className="flex items-center justify-between px-4">
          <button type="button" onClick={() => onGo({ kind: "overview" })} className="flex items-center gap-2.5 text-left">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/icon.svg`} width={30} height={30} alt="" className="rounded-lg" />
            <span className="text-[15px] font-semibold tracking-tight">zorua</span>
            {data && <span className="rounded-full bg-line px-2 py-0.5 font-mono text-xs text-dim">{data.version}</span>}
          </button>
          <button ref={closeBtn} type="button" onClick={onClose} aria-label="Close menu" className="rounded-lg p-1.5 text-dim hover:text-fg lg:hidden">
            <Icon name="close" />
          </button>
        </div>

        <div className="px-3 pt-4">
          <button
            type="button"
            onClick={onSearch}
            className="flex w-full items-center gap-2 rounded-lg border border-line-strong bg-bg px-2.5 py-1.5 text-left text-xs text-dim transition-colors hover:border-accent hover:text-fg"
          >
            <Icon name="search" className="size-3.5" />
            <span className="flex-1">Jump to…</span>
            <kbd className="rounded border border-line-strong px-1.5 py-px text-xs">⌘K</kbd>
          </button>
        </div>

        <ul className="mt-3 px-2">
          <Item icon="grid" active={view.kind === "overview"} onClick={() => onGo({ kind: "overview" })}>
            Overview
          </Item>
        </ul>
        {data && (
          <>
            <Group title="Codex" count={accounts("codex").length}>
              {accountItems("codex")}
            </Group>
            <Group title="Claude Code" count={accounts("claude").length}>
              {accountItems("claude")}
            </Group>
            <Group title="Providers" count={data.providers.length}>
              {data.providers.map((p) => (
                <Item
                  key={p.name}
                  tone={tones.get(`p:${p.name}`)}
                  active={at({ kind: "provider", name: p.name })}
                  onClick={() => onGo({ kind: "provider", name: p.name })}
                  right={<span className="text-xs text-dim">{p.agent}</span>}
                >
                  {p.name}
                </Item>
              ))}
            </Group>
          </>
        )}
        <ThemeSwitch />
      </nav>
    </>
  );
}
