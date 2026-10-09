import type { Check, ZoruaState } from "@/lib/types";
import { peak } from "./usage";
import type { View } from "./view";

export type Item = { key: string; tone: "danger" | "warn" | "info"; text: string; to: View };

export const DOT = { danger: "bg-danger", warn: "bg-warn", info: "bg-dim" } as const;

/** Everything that needs a look, worst first: sign-ins, nearly used up limits, missing usage, failed checks. */
export function attention(data: ZoruaState, checks: Record<string, Check>): Item[] {
  const items: Item[] = [];
  for (const a of data.accounts) {
    const to: View = { kind: "account", name: a.name };
    const p = peak(a);
    if (a.state === "none") items.push({ key: `a:${a.name}`, tone: "warn", text: `${a.name} is not signed in`, to });
    else if (a.usage.error) items.push({ key: `a:${a.name}`, tone: "warn", text: `${a.name}: ${a.usage.error}`, to });
    else if (p != null && p >= 80) items.push({ key: `a:${a.name}`, tone: "danger", text: `${a.name} at ${p}% of its limit`, to });
    else if (a.usage.shadowed_by?.length) items.push({ key: `a:${a.name}`, tone: "warn", text: `${a.name}: relay hidden by ${a.usage.shadowed_by[0].file}`, to });
    else if (a.state === "ok" && a.usage.windows.length === 0 && a.agent === "claude") items.push({ key: `a:${a.name}`, tone: "info", text: `${a.name}: no usage data yet`, to });
  }
  for (const p of data.providers) {
    const c = checks[p.name];
    if (c && c.status !== "ok") items.push({ key: `p:${p.name}`, tone: c.status === "fail" ? "danger" : "warn", text: `${p.name}: ${c.detail}`, to: { kind: "provider", name: p.name } });
  }
  const rank = { danger: 0, warn: 1, info: 2 };
  return items.sort((x, y) => rank[x.tone] - rank[y.tone]);
}
