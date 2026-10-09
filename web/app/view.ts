export type View = { kind: "overview" } | { kind: "account"; name: string } | { kind: "provider"; name: string };

const NAME = /^[A-Za-z0-9_-]{1,32}$/;

/** `#/provider/kimi` ↔ { kind: "provider", name: "kimi" }; anything else is the overview. */
export function parseHash(hash: string): View {
  const [, kind, name] = hash.replace(/^#/, "").split("/");
  if ((kind === "account" || kind === "provider") && name && NAME.test(name)) return { kind, name };
  return { kind: "overview" };
}

export function formatHash(v: View): string {
  return v.kind === "overview" ? "#/" : `#/${v.kind}/${v.name}`;
}

export const sameView = (a: View, b: View) => formatHash(a) === formatHash(b);
