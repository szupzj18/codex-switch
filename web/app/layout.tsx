import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Zorua — accounts and usage",
  description: "Local view of your Zorua accounts, usage and providers.",
};

// Runs before first paint so a saved light/dark choice and row density do not flash the defaults.
const THEME_SCRIPT = `try{var d=document.documentElement,t=localStorage.getItem("zorua-theme");if(t==="light"||t==="dark")d.dataset.theme=t;if(localStorage.getItem("zorua-density")==="compact")d.dataset.density="compact"}catch(e){}`;

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
      </head>
      <body className="min-h-screen antialiased">
        <a href="#main" className="sr-only rounded-lg bg-accent px-3 py-2 text-xs font-semibold text-on-accent focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:z-[60]">
          Skip to content
        </a>
        {children}
      </body>
    </html>
  );
}
