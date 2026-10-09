"use client";

import { useState } from "react";
import { actionBtn } from "./ui";

/** Write to the clipboard, falling back to a hidden textarea where the Clipboard API is unavailable. */
export async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const t = document.createElement("textarea");
    t.value = text;
    t.style.position = "fixed";
    t.style.opacity = "0";
    document.body.appendChild(t);
    t.select();
    const ok = document.execCommand("copy");
    t.remove();
    if (!ok) throw new Error("copy failed");
  }
}

/**
 * Copies a value that is fetched on click, so a masked key can be copied without being shown.
 * `box` is the bordered button next to a field, `action` the one in a row of actions.
 */
export function CopyButton({ get, label, text = "copy", variant = "box" }: { get: () => Promise<string>; label: string; text?: string; variant?: "box" | "action" }) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");
  const click = async () => {
    try {
      await copyText(await get());
      setState("copied");
    } catch {
      setState("failed");
    }
    setTimeout(() => setState("idle"), 1500);
  };
  const shown = state === "copied" ? "copied" : state === "failed" ? "failed" : text;
  const tone = state === "copied" ? "text-accent" : state === "failed" ? "text-danger" : "text-dim hover:text-accent";
  const flash = state === "copied" ? "border-accent" : state === "failed" ? "border-danger" : "";
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={click}
      className={variant === "box" ? `w-14 rounded-md border border-line px-2 py-1 text-[11px] ${tone}` : `${actionBtn} ${tone} ${flash}`}
    >
      {shown}
    </button>
  );
}

/** Quote a path for a POSIX shell. */
export const shellQuote = (s: string) => `'${s.replace(/'/g, `'\\''`)}'`;
