/** Small bordered buttons for the actions on a row or page header; `danger` turns red on hover. */
const ACTION = "rounded-md border border-line px-2.5 py-1 text-xs text-dim transition-colors disabled:opacity-50";
export const actionBtn = `${ACTION} hover:border-accent hover:text-accent`;
export const dangerBtn = `${ACTION} hover:border-danger hover:text-danger`;

/** The row of actions under an entry. */
export const actionRow = "mt-3 flex flex-wrap items-center gap-2";
export const rowActions = "flex flex-wrap items-center gap-2 sm:col-span-2";
