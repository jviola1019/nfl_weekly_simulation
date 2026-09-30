import { randomBytes, scrypt as scryptCb, timingSafeEqual, type ScryptOptions } from "node:crypto";
import { promisify } from "node:util";

/**
 * scrypt password storage (profile from the fantasy_football_dashboard audit F-005):
 * N=65536, r=8, p=2 is an OWASP-listed equivalent profile at 64 MiB. maxmem must be
 * set explicitly (Node's default is 32 MiB). Format: scrypt2$<salt b64>$<key b64>.
 */
const scryptAsync = promisify(scryptCb) as (pw: string | Buffer, salt: Buffer, keylen: number, opts: ScryptOptions) => Promise<Buffer>;
const PROFILE = { version: "scrypt2", options: { N: 65536, r: 8, p: 2, maxmem: 2 * 128 * 65536 * 8 } as ScryptOptions };
const KEYLEN = 32;

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scryptAsync(password.normalize("NFKC"), salt, KEYLEN, PROFILE.options);
  return `${PROFILE.version}$${salt.toString("base64")}$${key.toString("base64")}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [version, saltB64, keyB64] = stored.split("$");
  if (version !== PROFILE.version || !saltB64 || !keyB64) return false;
  const expected = Buffer.from(keyB64, "base64");
  const got = await scryptAsync(password.normalize("NFKC"), Buffer.from(saltB64, "base64"), expected.length, PROFILE.options);
  return got.length === expected.length && timingSafeEqual(got, expected);
}

/** A fixed hash to verify against when the account does not exist (timing equalizer). */
export const DUMMY_HASH = "scrypt2$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
