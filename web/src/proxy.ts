import NextAuth from "next-auth";
import { NextResponse } from "next/server";
import { authConfig } from "@/lib/auth.config";
import { buildCsp, CSP_HEADER_NAME } from "@/lib/security/csp";

/**
 * Next 16 proxy (formerly middleware). Two jobs with different scopes:
 *   1. CSP with a per-request nonce on every document request;
 *   2. defence-in-depth gating of /desk. requireUser() in the page is the
 *      authoritative check; the proxy cannot see a revoked session.
 */
const { auth } = NextAuth(authConfig);
const PROTECTED = ["/desk"];

export default auth((request) => {
  const nonce = crypto.randomUUID().replace(/-/g, "");
  const csp = buildCsp({ nonce, isDev: process.env.NODE_ENV !== "production" });
  const path = request.nextUrl.pathname;
  if (PROTECTED.some((p) => path === p || path.startsWith(`${p}/`)) && !request.auth?.user) {
    // same-origin login page (built from this request, never from AUTH_URL)
    return NextResponse.redirect(new URL("/login", request.nextUrl.origin));
  }
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set(CSP_HEADER_NAME, csp);
  const response = NextResponse.next({ request: { headers: requestHeaders } });
  response.headers.set(CSP_HEADER_NAME, csp);
  return response;
});

export const config = {
  matcher: [
    {
      source: "/((?!api|_next/static|_next/image|favicon.ico|icon.svg).*)",
      missing: [
        { type: "header", key: "next-router-prefetch" },
        { type: "header", key: "purpose", value: "prefetch" }
      ]
    }
  ]
};
