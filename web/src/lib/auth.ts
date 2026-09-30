import NextAuth from "next-auth";
import Credentials from "next-auth/providers/credentials";
import { headers } from "next/headers";
import { getDb } from "../db";
import { authConfig } from "./auth.config";
import { authenticate } from "./auth/credentials";

export const { handlers, auth, signIn, signOut } = NextAuth({
  ...authConfig,
  providers: [
    Credentials({
      credentials: { email: { label: "Email", type: "email" }, password: { label: "Password", type: "password" } },
      authorize: async (creds) => {
        const email = typeof creds?.email === "string" ? creds.email.trim() : "";
        const password = typeof creds?.password === "string" ? creds.password : "";
        if (!email || !password || password.length > 256) return null;
        const h = await headers();
        const ip = h.get("x-forwarded-for")?.split(",")[0]?.trim() || h.get("x-real-ip") || "unknown";
        const user = await authenticate(getDb(), email, password, ip);
        return user ? { id: user.id, email: user.email, sessionVersion: user.sessionVersion } : null;
      }
    })
  ]
});
