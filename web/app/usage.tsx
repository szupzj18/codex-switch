import type { Account, UsageWindow } from "@/lib/types";

export const PLAN_STYLE: Record<string, string> = {
  pro: "text-accent",
  plus: "text-accent",
  promax: "text-violet",
  max: "text-violet",
  team: "text-info",
  enterprise: "text-info",
};

export function windowLabel(s: number | null) {
  if (!s) return "?";
  return s < 86400 ? `${Math.round(s / 3600)}H` : `${Math.round(s / 86400)}D`;
}

export function span(s: number) {
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d && h) return `${d}d${h}h`;
  if (d) return `${d}d`;
  if (h) return `${h}h${m}m`;
  return `${m}m`;
}

export function ago(s: number) {
  return s < 3600 ? `${Math.floor(s / 60)}m ago` : `${span(s)} ago`;
}

export function barColor(p: number) {
  return p >= 80 ? "bg-danger" : p >= 50 ? "bg-warn" : "bg-accent";
}

export function textColor(p: number) {
  return p >= 80 ? "text-danger" : p >= 50 ? "text-warn" : "text-dim";
}

/** The highest used percentage over an account's windows, or null when it has no usage data. */
export function peak(a: Account): number | null {
  const ps = a.usage.windows.map((w) => w.used_percent).filter((p): p is number => p != null);
  return ps.length ? Math.max(...ps) : null;
}

/** Why an account shows no usage bars (or a problem alongside them). */
export function usageNote(a: Account): string | null {
  if (a.usage.error) return a.usage.error;
  if (a.state !== "ok") return a.state === "apikey" ? "API key login" : a.state === "none" ? "not signed in" : a.state;
  if (a.usage.windows.length === 0) {
    if (a.agent !== "claude") return "no usage data";
    if (a.usage.expired?.length) return null; // the panel shows what reset and when
    const hidden = a.usage.shadowed_by?.[0];
    if (hidden) return `no usage yet — ${hidden.file} has its own status line, which hides the relay in sessions started in ${hidden.dir}. Run 'zorua hook install ${a.name} --shadows'`;
    // Sessions that were already running when the relay was installed never call it.
    return a.usage.relay ? "no usage yet — the relay is installed; restart claude under this account and send a message" : `no usage yet — run 'zorua hook install ${a.name}', then use claude once`;
  }
  return null;
}

export function Bar({ w }: { w: UsageWindow }) {
  const p = Math.max(0, Math.min(100, w.used_percent ?? 0));
  return (
    <div className="min-w-0">
      <div className="flex items-baseline justify-between gap-2">
        <span className="rounded bg-line px-1.5 py-px font-mono text-xs font-medium tracking-wide text-dim">{windowLabel(w.window_seconds)}</span>
        <span className={`text-sm font-semibold tabular-nums ${p >= 50 ? textColor(p) : ""}`}>{p}%</span>
      </div>
      <div
        className="mt-1.5 h-2 overflow-hidden rounded-full bg-line"
        role="progressbar"
        aria-valuenow={p}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={`${windowLabel(w.window_seconds)} usage`}
      >
        <div className={`h-full rounded-full transition-[width] duration-500 ${barColor(p)}`} style={{ width: `${p}%` }} />
      </div>
      {w.reset_after_seconds != null && <div className="mt-1.5 text-xs text-dim">resets in {span(w.reset_after_seconds)}</div>}
    </div>
  );
}

/** A cache older than this means no session is running to refresh it. */
const STALE_SECONDS = 600;

/** A window that reset since the last report: its old percentage is gone and the new one is unknown. */
function Expired({ window_seconds, reset_ago_seconds }: { window_seconds: number; reset_ago_seconds: number }) {
  return (
    <div className="min-w-0">
      <div className="flex items-baseline justify-between gap-2 text-xs">
        <span className="text-dim">{windowLabel(window_seconds)}</span>
        <span className="text-dim">–</span>
      </div>
      <div className="mt-1 h-1.5 rounded-full border border-dashed border-dim/40" aria-hidden />
      <div className="mt-1 text-xs text-dim">reset {ago(reset_ago_seconds)}, new usage unknown</div>
    </div>
  );
}

/** An account's usage: bars, windows that have reset, how old the numbers are, and why there are none. */
export function UsagePanel({ a, roomy = false }: { a: Account; roomy?: boolean }) {
  const ws = a.usage.windows;
  const expired = a.usage.expired ?? [];
  const note = usageNote(a);
  const age = a.usage.age_seconds;
  const gap = roomy ? "gap-6" : "gap-4";
  const top = roomy ? "mt-3" : "mt-2";
  return (
    <div>
      {ws.length + expired.length > 0 ? (
        <div className={`grid grid-cols-2 ${gap}`}>
          {ws.map((w, i) => (
            <Bar key={i} w={w} />
          ))}
          {expired.map((e, i) => (
            <Expired key={i} {...e} />
          ))}
        </div>
      ) : (
        note && <div className="text-xs text-dim">{note}</div>
      )}
      {ws.length + expired.length > 0 && age != null && (
        <div className={`${top} text-xs ${age >= STALE_SECONDS ? "text-warn" : "text-dim"}`}>
          from its last session, {ago(age)}
          {age >= STALE_SECONDS && " — no session is open to refresh it"}
        </div>
      )}
      {expired.length > 0 && ws.length === 0 && (age == null || age < STALE_SECONDS) && <div className="mt-1 text-xs text-dim">waiting for a new claude session to report the new window</div>}
      {ws.length + expired.length > 0 && note && <div className="mt-2 text-xs text-danger">{note}</div>}
    </div>
  );
}
