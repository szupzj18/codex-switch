"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { Icon, type IconName } from "./icons";

export type Command = {
  id: string;
  group: string;
  label: string;
  hint?: string;
  icon?: IconName;
  /** Extra words the search also matches. */
  keywords?: string;
  run: () => void;
};

/** Every word typed must appear in the label, hint or keywords; a label that starts with the query ranks first. */
function search(commands: Command[], q: string): Command[] {
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) return commands;
  const scored: [number, Command][] = [];
  for (const c of commands) {
    const label = c.label.toLowerCase();
    const hay = `${label} ${c.hint ?? ""} ${c.keywords ?? ""} ${c.group}`.toLowerCase();
    if (!words.every((w) => hay.includes(w))) continue;
    scored.push([label.startsWith(words[0]) ? 0 : label.includes(words[0]) ? 1 : 2, c]);
  }
  return scored.sort((a, b) => a[0] - b[0]).map(([, c]) => c);
}

/** ⌘K: jump to an account or provider, run an action, copy a command. Mounted only while open. */
export function Palette({ commands, onClose }: { commands: Command[]; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const [q, setQ] = useState("");
  const [active, setActive] = useState(0);
  const uid = useId();
  const shown = useMemo(() => search(commands, q), [commands, q]);
  const current = Math.min(active, Math.max(0, shown.length - 1));

  useEffect(() => {
    const d = ref.current;
    if (d && !d.open) d.showModal();
  }, []);

  useEffect(() => {
    list.current?.querySelector(`[data-index="${current}"]`)?.scrollIntoView({ block: "nearest" });
  }, [current]);

  const run = (c: Command | undefined) => {
    if (!c) return;
    ref.current?.close();
    c.run();
  };

  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((current + 1) % Math.max(1, shown.length));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((current - 1 + shown.length) % Math.max(1, shown.length));
    } else if (e.key === "Enter") {
      e.preventDefault();
      run(shown[current]);
    }
  };

  let lastGroup = "";
  return (
    <dialog
      ref={ref}
      data-palette
      aria-label="Command palette"
      onClose={onClose}
      onClick={(e) => e.target === ref.current && ref.current?.close()}
      className="m-0 mx-auto mt-[12vh] w-[min(92vw,36rem)] overflow-hidden rounded-2xl border border-line-strong bg-panel p-0 text-fg shadow-pop backdrop:bg-black/60 backdrop:backdrop-blur-sm open:animate-pop"
    >
      <div className="flex items-center gap-3 border-b border-line px-4">
        <Icon name="search" className="size-4 text-dim" />
        <input
          autoFocus
          role="combobox"
          aria-expanded
          aria-controls={`${uid}-list`}
          aria-activedescendant={shown[current] ? `${uid}-${current}` : undefined}
          aria-label="Search accounts, providers and actions"
          value={q}
          onChange={(e) => {
            setQ(e.target.value);
            setActive(0);
          }}
          onKeyDown={onKey}
          placeholder="Jump to an account, provider or action…"
          className="h-12 flex-1 bg-transparent text-sm outline-none placeholder:text-dim/70"
          spellCheck={false}
          autoComplete="off"
        />
        <kbd className="rounded border border-line-strong px-1.5 py-px text-[10px] text-dim">esc</kbd>
      </div>
      <div ref={list} id={`${uid}-list`} role="listbox" className="max-h-[min(24rem,52vh)] overflow-y-auto p-2">
        {shown.length === 0 && <p className="px-3 py-8 text-center text-xs text-dim">Nothing matches “{q}”.</p>}
        {shown.map((c, i) => {
          const header = !q && c.group !== lastGroup;
          lastGroup = c.group;
          return (
            <div key={c.id}>
              {header && <div className="px-3 pb-1 pt-2.5 text-[11px] font-medium uppercase tracking-wider text-dim">{c.group}</div>}
              <div
                id={`${uid}-${i}`}
                data-index={i}
                role="option"
                aria-selected={i === current}
                onMouseMove={() => i !== current && setActive(i)}
                onClick={() => run(c)}
                className={`flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2 text-[13px] ${i === current ? "bg-accent/10 text-accent" : ""}`}
              >
                {c.icon && <Icon name={c.icon} className={i === current ? "" : "text-dim"} />}
                <span className="min-w-0 flex-1 truncate">{c.label}</span>
                {c.hint && <span className="truncate text-xs text-dim">{c.hint}</span>}
                {i === current && <Icon name="enter" className="size-3.5" />}
              </div>
            </div>
          );
        })}
      </div>
      <div className="flex gap-4 border-t border-line px-4 py-2 text-[11px] text-dim">
        <span>↑↓ select</span>
        <span>↵ run</span>
        <span>esc close</span>
      </div>
    </dialog>
  );
}
