// Plain ESM (see src/lib/security/securityHeaders.mjs for why).
import { fileURLToPath } from "node:url";
import { STATIC_SECURITY_HEADERS } from "./src/lib/security/securityHeaders.mjs";

/** @type {import('next').NextConfig} */
const nextConfig = {
  poweredByHeader: false,
  // The R engine lives one directory up; bundles are read at ingest time, not by pages.
  outputFileTracingRoot: fileURLToPath(new URL("..", import.meta.url)),
  async headers() {
    return [
      { source: "/api/:path*", headers: [{ key: "Cache-Control", value: "no-store, max-age=0, must-revalidate" }] },
      { source: "/:path*", headers: [...STATIC_SECURITY_HEADERS] }
    ];
  }
};

export default nextConfig;
