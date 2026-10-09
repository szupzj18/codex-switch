export type UsageWindow = {
  window_seconds: number | null;
  used_percent: number | null;
  reset_after_seconds: number | null;
};

export type Account = {
  name: string;
  agent: "codex" | "claude";
  home: string;
  state: string;
  email: string | null;
  plan: string | null;
  until: string | null;
  usage: { windows: UsageWindow[]; error: string | null; age_seconds: number | null; /** Claude accounts: is the status-line relay installed (null for Codex, absent from an older zorua) */ relay?: boolean | null; /** project settings whose own status line hides the relay (Claude; absent from an older zorua) */ shadowed_by?: { file: string; dir: string }[] | null };
};

export type Provider = {
  name: string;
  agent: "codex" | "claude";
  endpoint: string;
  models: Record<string, string>;
};

export type Binding = { name: string; dir: string; kind: string | null };

export type ZoruaState = {
  version: string;
  generated_at: number;
  accounts: Account[];
  providers: Provider[];
  bindings: Binding[];
};

export type LoginJob = {
  name: string;
  status: "running" | "done" | "failed";
  output: string;
  urls: string[];
  startedAt: number;
};

/** The result of `zorua provider check`: is the endpoint reachable and the key accepted. */
export type Check = {
  status: "ok" | "warn" | "fail";
  http: number | null;
  ms: number;
  via: string;
  detail: string;
  checked_at: number;
};

export type StateResponse = {
  data: ZoruaState;
  stale: boolean;
  error: string | null;
  checks: Record<string, Check>;
};

/** What `zorua provider get` prints: the editable view of one provider. */
export type ProviderDoc =
  | { agent: "claude"; env: Record<string, string>; models: Record<string, string> }
  | { agent: "codex"; base_url: string; key: string; model: string; wire_api: string; models: Record<string, string> };
