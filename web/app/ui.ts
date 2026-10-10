/** Small bordered buttons for the actions on a row or page header; `danger` turns red on hover. */
const ACTION = "inline-flex items-center rounded-lg border border-line-strong px-2.5 py-1 text-xs font-medium text-dim transition-colors disabled:opacity-50";
export const actionBtn = `${ACTION} hover:border-accent hover:text-accent`;
export const dangerBtn = `${ACTION} hover:border-danger hover:text-danger`;

/** The row of actions under an entry. */
export const actionRow = "mt-3 flex flex-wrap items-center gap-2";
export const rowActions = "flex flex-wrap items-center gap-2 sm:col-span-2";

/** Form buttons and inputs, shared by the dialogs and the provider editor. */
export const primaryBtn = "rounded-lg bg-accent px-3 py-1.5 text-xs font-semibold text-on-accent transition hover:brightness-110 disabled:opacity-50";
export const ghostBtn = "rounded-lg border border-line-strong px-3 py-1.5 text-xs text-dim transition-colors hover:text-fg disabled:opacity-40";
export const outlineBtn = "rounded-lg border border-accent/60 px-3 py-1.5 text-xs font-medium text-accent transition-colors hover:bg-accent/10";
export const fieldCls = "w-full rounded-lg border border-line-strong bg-bg px-2.5 py-1.5 text-sm text-fg outline-none transition-colors placeholder:text-dim/60 focus:border-accent";

/** A bordered surface, and the heading + count badge that sits above one. */
export const card = "squircle overflow-hidden rounded-2xl border border-line bg-panel shadow-card";
export const sectionTitle = "mb-3 flex items-center gap-2 text-[13px] font-semibold tracking-tight";
export const countBadge = "rounded-full bg-line px-2 py-0.5 text-xs font-medium tabular-nums text-dim";

/** Inline messages. */
export const alertDanger = "rounded-lg border border-danger/40 bg-danger/10 px-3 py-2 text-xs text-danger";
