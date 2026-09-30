import type { NextAuthConfig } from "next-auth";

/**
 * Edge-safe Auth.js config shared by the Node handlers (src/lib/auth.ts) and the proxy
 * (src/proxy.ts). No database access here: the proxy only verifies the JWT, and
 * requireUser() re-checks the database at each protected read.
 */
export const authConfig = {
  trustHost: true,
  session: { strategy: "jwt", maxAge: 12 * 60 * 60 },
  pages: { signIn: "/login" },
  providers: [],
  callbacks: {
    jwt: ({ token, user }) => {
      if (user) {
        token.id = user.id;
        token.sv = (user as { sessionVersion?: number }).sessionVersion;
      }
      return token;
    },
    session: ({ session, token }) => {
      if (session.user && token.id) session.user.id = token.id as string;
      if (session.user) (session.user as { sessionVersion?: number }).sessionVersion = token.sv as number | undefined;
      return session;
    }
  }
} satisfies NextAuthConfig;
