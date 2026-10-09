"use client";

import { useEffect, useState } from "react";

type Mode = "auto" | "light" | "dark";
const KEY = "zorua-theme";
const MODES: Mode[] = ["auto", "light", "dark"];

/** Applied before first paint by THEME_SCRIPT in layout.tsx; this is the interactive half. */
export function ThemeSwitch() {
  const [mode, setMode] = useState<Mode>("auto");

  useEffect(() => {
    try {
      const saved = localStorage.getItem(KEY);
      if (saved === "light" || saved === "dark") setMode(saved);
    } catch {}
  }, []);

  const choose = (m: Mode) => {
    setMode(m);
    if (m === "auto") document.documentElement.removeAttribute("data-theme");
    else document.documentElement.dataset.theme = m;
    try {
      if (m === "auto") localStorage.removeItem(KEY);
      else localStorage.setItem(KEY, m);
    } catch {}
  };

  return (
    <div role="radiogroup" aria-label="Theme" className="mx-3 mt-4 flex overflow-hidden rounded-md border border-line text-[11px]">
      {MODES.map((m) => (
        <button
          key={m}
          type="button"
          role="radio"
          aria-checked={mode === m}
          onClick={() => choose(m)}
          className={`flex-1 px-2 py-1 ${mode === m ? "bg-accent text-on-accent" : "text-dim hover:text-fg"}`}
        >
          {m}
        </button>
      ))}
    </div>
  );
}
