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

export type ZoruaState = {
  version: string;
  generated_at: number;
  accounts: Account[];
  providers: Provider[];
};

export type StateResponse = {
  data: ZoruaState;
  stale: boolean;
  error: string | null;
};
