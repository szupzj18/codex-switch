import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Zorua — accounts and usage",
  description: "Local view of your Zorua accounts, usage and providers.",
};

// Runs before first paint so a saved light/dark choice does not flash the other theme.
const THEME_SCRIPT = `try{var t=localStorage.getItem("zorua-theme");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch(e){}`;

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
      </head>
      <body className="min-h-screen antialiased">{children}</body>
    </html>
  );
}
