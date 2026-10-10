/** Single-key shortcuts. They are ignored while a field has focus or a dialog is open; ⌘K and / also work in the palette. */
export const SHORTCUTS: [keys: string, what: string][] = [
  ["⌘K  /  Ctrl+K  /  /", "Open the command palette"],
  ["r", "Refresh now"],
  ["g  then  o", "Go to the overview"],
  ["a", "Add an account"],
  ["p", "Add a provider"],
  ["b", "Bind a directory"],
  ["t", "Switch theme: auto → light → dark"],
  ["d", "Compact or comfortable rows"],
  ["?", "Show this list"],
  ["Esc", "Close a dialog or the palette"],
];
