import type { NextConfig } from "next";

// The static demo: no server, so no route handlers (build.sh removes app/api) and no cacheComponents.
const base = process.env.ZORUA_DEMO_BASE ?? "";

const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
  ...(base ? { basePath: base } : {}),
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
