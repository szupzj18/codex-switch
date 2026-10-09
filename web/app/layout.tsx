import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Zorua — accounts and usage",
  description: "Local, read-only view of your Zorua accounts, usage and providers.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en">
      <body className="min-h-screen antialiased">{children}</body>
    </html>
  );
}
