"use client";

import { useEffect, useState } from "react";
import { Icon, type IconName } from "./icons";

export type Mode = "auto" | "light" | "dark";
const KEY = "zorua-theme";
const EVENT = "zorua-theme";
export const MODES: Mode[] = ["auto", "light", "dark"];
const ICON: Record<Mode, IconName> = { auto: "monitor", light: "sun", dark: "moon" };

function readMode(): Mode {
  try {
    const saved = localStorage.getItem(KEY);
    if (saved === "light" || saved === "dark") return saved;
  } catch {}
  return "auto";
}

/** Apply and remember a theme. Also used by the command palette, so the switch listens for the event. */
export function setThemeMode(m: Mode) {
  if (m === "auto") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.dataset.theme = m;
  try {
    if (m === "auto") localStorage.removeItem(KEY);
    else localStorage.setItem(KEY, m);
  } catch {}
  window.dispatchEvent(new Event(EVENT));
}

/** auto → light → dark → auto, for the `t` shortcut. */
export function cycleTheme() {
  setThemeMode(MODES[(MODES.indexOf(readMode()) + 1) % MODES.length]);
}

/** Applied before first paint by THEME_SCRIPT in layout.tsx; this is the interactive half. */
export function ThemeSwitch() {
  const [mode, setMode] = useState<Mode>("auto");

  useEffect(() => {
    const sync = () => setMode(readMode());
    sync();
    window.addEventListener(EVENT, sync);
    return () => window.removeEventListener(EVENT, sync);
  }, []);

  return (
    <div role="radiogroup" aria-label="Theme" className="mx-3 mt-5 flex rounded-xl bg-line/70 p-0.5 text-[11px]">
      {MODES.map((m) => (
        <button
          key={m}
          type="button"
          role="radio"
          aria-checked={mode === m}
          onClick={() => setThemeMode(m)}
          className={`flex flex-1 items-center justify-center gap-1.5 rounded-[10px] px-2 py-1.5 font-medium transition-colors ${mode === m ? "bg-panel text-fg shadow-sm" : "text-dim hover:text-fg"}`}
        >
          <Icon name={ICON[m]} className="size-3.5" />
          {m}
        </button>
      ))}
    </div>
  );
}
