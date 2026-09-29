import { describe, expect, it } from "vitest";
import { DUMMY_HASH, hashPassword, verifyPassword } from "./passwords";

describe("scrypt2 passwords", () => {
  it("round-trips and salts every hash", async () => {
    const a = await hashPassword("correct horse battery staple");
    const b = await hashPassword("correct horse battery staple");
    expect(a).toMatch(/^scrypt2\$[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+$/);
    expect(a).not.toBe(b);
    expect(await verifyPassword("correct horse battery staple", a)).toBe(true);
    expect(await verifyPassword("correct horse battery stapl", a)).toBe(false);
  });

  it("normalizes to NFKC so the same password typed two ways verifies", async () => {
    const h = await hashPassword("ﬁnal-pass"); // U+FB01 ligature
    expect(await verifyPassword("final-pass", h)).toBe(true);
  });

  it("rejects malformed or foreign hashes, and the dummy hash never verifies", async () => {
    expect(await verifyPassword("x", "")).toBe(false);
    expect(await verifyPassword("x", "bcrypt$abc$def")).toBe(false);
    expect(await verifyPassword("x", "scrypt2$onlysalt")).toBe(false);
    expect(await verifyPassword("", DUMMY_HASH)).toBe(false);
  });
});
