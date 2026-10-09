import type { Check } from "@/lib/types";
import { actionBtn } from "./ui";
import { ago } from "./usage";

export async function checkProvider(name: string): Promise<Check> {
  const r = await fetch("/api/check", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Zorua-Web": "1" },
    body: JSON.stringify({ name }),
  });
  const body = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(body.error ?? `HTTP ${r.status}`);
  return body.check as Check;
}

/** Merge two result sets, keeping the newer result for each provider. */
export function newest(a: Record<string, Check>, b: Record<string, Check>): Record<string, Check> {
  const out = { ...a };
  for (const [k, c] of Object.entries(b)) if (!out[k] || c.checked_at >= out[k].checked_at) out[k] = c;
  return out;
}

const TONE = { ok: "text-accent", warn: "text-warn", fail: "text-danger" } as const;
const MARK = { ok: "✓", warn: "!", fail: "✗" } as const;

/** The result of the last provider check, or "not checked", with a check link. */
export function CheckBadge({ check, checking, onCheck }: { check?: Check; checking: boolean; onCheck: () => void }) {
  return (
    <span className="inline-flex flex-wrap items-center gap-x-3 gap-y-1.5 text-xs">
      {checking ? (
        <span className="text-dim">checking…</span>
      ) : check ? (
        <span className={TONE[check.status]} title={`${check.via}${check.http != null ? ` · HTTP ${check.http}` : ""}`}>
          {MARK[check.status]} {check.detail}
          {check.status === "ok" && ` · ${check.ms}ms`}
          <span className="text-dim"> · {ago(Math.max(0, Math.floor(Date.now() / 1000) - check.checked_at))}</span>
        </span>
      ) : (
        <span className="text-dim">not checked</span>
      )}
      <button type="button" onClick={onCheck} disabled={checking} className={actionBtn}>
        {check ? "check again" : "check"}
      </button>
    </span>
  );
}
