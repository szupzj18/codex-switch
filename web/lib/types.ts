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
  usage: { windows: UsageWindow[]; error: string | null; age_seconds: number | null };
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

export type StateResponse = {
  data: ZoruaState;
  stale: boolean;
  error: string | null;
};

/** What `zorua provider get` prints: the editable view of one provider. */
export type ProviderDoc =
  | { agent: "claude"; env: Record<string, string>; models: Record<string, string> }
  | { agent: "codex"; base_url: string; key: string; model: string; wire_api: string; models: Record<string, string> };
