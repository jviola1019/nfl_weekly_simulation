import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  databaseUrl,
  DEFAULT_WINDOWS_PG_BIN,
  envAdditions,
  missingPointers,
  needsBuild,
  parseEnvFile,
  pgExecutable,
  redactUrl,
  resolveLocalConfig,
  selectBundleDirs
} from "./config";

const ROOT = join("repo-root");

describe("resolveLocalConfig", () => {
  it("defaults: a private cluster under .local/pgdata on port 5434, bundles/ at the repo root", () => {
    const cfg = resolveLocalConfig({}, "win32", ROOT);
    expect(cfg.pgBin).toBe(DEFAULT_WINDOWS_PG_BIN);
    expect(cfg.pgData).toBe(join(ROOT, ".local", "pgdata"));
    expect(cfg.pgPort).toBe(5434);
    expect(cfg.bundlesDir).toBe(join(ROOT, "bundles"));
    expect(cfg.envFile).toBe(join(ROOT, "web", ".env.local"));
    expect(cfg.credentialsFile).toBe(join(ROOT, ".local", "pgdata", "nfl_local_credentials.json"));
    expect([cfg.dbName, cfg.dbUser]).toEqual(["nfl_local", "nfl_local"]);
  });

  it("finds PostgreSQL on PATH outside Windows", () => {
    expect(resolveLocalConfig({}, "linux", ROOT).pgBin).toBeNull();
    expect(resolveLocalConfig({}, "darwin", ROOT).pgBin).toBeNull();
  });

  it("takes PG_BIN, NFL_LOCAL_PGDATA, NFL_LOCAL_PGPORT and NFL_LOCAL_BUNDLES from the environment", () => {
    const cfg = resolveLocalConfig(
      { PG_BIN: "/opt/pg/bin", NFL_LOCAL_PGDATA: "/data/pg", NFL_LOCAL_PGPORT: "5440", NFL_LOCAL_BUNDLES: "/b" },
      "linux",
      ROOT
    );
    expect([cfg.pgBin, cfg.pgData, cfg.pgPort, cfg.bundlesDir]).toEqual(["/opt/pg/bin", "/data/pg", 5440, "/b"]);
    expect(cfg.serverLog).toBe(join("/data/pg", "nfl_local_server.log"));
  });

  it("refuses a port that is not a whole number from 1024 to 65535", () => {
    for (const bad of ["80", "70000", "54x4", "5434.5"]) {
      expect(() => resolveLocalConfig({ NFL_LOCAL_PGPORT: bad }, "linux", ROOT), bad).toThrow("NFL_LOCAL_PGPORT");
    }
  });
});

describe("executables and URLs", () => {
  it("adds .exe on Windows and uses the bare name on PATH", () => {
    expect(pgExecutable(DEFAULT_WINDOWS_PG_BIN, "pg_ctl", "win32")).toBe(join(DEFAULT_WINDOWS_PG_BIN, "pg_ctl.exe"));
    expect(pgExecutable(null, "pg_ctl", "linux")).toBe("pg_ctl");
  });

  it("encodes the password in the URL and never prints it", () => {
    const cfg = resolveLocalConfig({}, "linux", ROOT);
    const url = databaseUrl(cfg, "p@ss/w:rd");
    expect(url).toBe("postgres://nfl_local:p%40ss%2Fw%3Ard@127.0.0.1:5434/nfl_local");
    expect(databaseUrl(cfg, "x", "postgres")).toBe("postgres://nfl_local:x@127.0.0.1:5434/postgres");
    expect(redactUrl(url)).toBe("postgres://nfl_local:***@127.0.0.1:5434/nfl_local");
  });
});

describe(".env.local", () => {
  it("parses KEY=value lines, ignoring comments, `export` and quotes", () => {
    expect(parseEnvFile('# c\nexport A=1\r\nB="two words"\n  C = \'3\'\nnot a line\n')).toEqual({ A: "1", B: "two words", C: "3" });
  });

  it("adds only the keys that are absent", () => {
    expect(envAdditions({ AUTH_SECRET: "s" }, { DATABASE_URL: "u", AUTH_SECRET: "new" })).toEqual(["DATABASE_URL=u"]);
    expect(envAdditions({ DATABASE_URL: "mine", AUTH_SECRET: "s" }, { DATABASE_URL: "u", AUTH_SECRET: "new" })).toEqual([]);
  });
});

describe("selectBundleDirs", () => {
  const m = (generated_utc: string, bundle_kind = "weekly") => ({ generated_utc, bundle_kind });

  it("ingests oldest first, so the newest weekly bundle ends up published", () => {
    const { ingest } = selectBundleDirs([
      { name: "2026-w04-x", manifest: m("2026-10-03T12:00:00Z") },
      { name: "backtest-nfl-games-v1-7244a0bc", manifest: m("2026-09-29T21:00:00Z", "backtest") },
      { name: "2024-w15-sim-20261001T120000Z", manifest: m("2026-10-01T12:00:00Z") }
    ]);
    expect(ingest).toEqual(["backtest-nfl-games-v1-7244a0bc", "2024-w15-sim-20261001T120000Z", "2026-w04-x"]);
  });

  it("breaks ties by name and reports directories without a readable manifest", () => {
    const out = selectBundleDirs([
      { name: "b", manifest: m("2026-10-01T00:00:00Z") },
      { name: "a", manifest: m("2026-10-01T00:00:00Z") },
      { name: "notes", manifest: null },
      { name: "half", manifest: { generated_utc: "2026-10-01T00:00:00Z" } }
    ]);
    expect(out).toEqual({ ingest: ["a", "b"], skipped: ["half", "notes"] });
  });
});

describe("missingPointers", () => {
  it("names what the database does not publish yet and what writes it", () => {
    expect(missingPointers(["weekly", "backtest_games"])).toEqual([]);
    expect(missingPointers(["backtest_games"]).map((m) => m.pointer)).toEqual(["weekly"]);
    expect(missingPointers([]).map((m) => m.pointer)).toEqual(["weekly", "backtest_games"]);
    expect(missingPointers([])[0]!.hint).toContain("Rscript run_week.R <week> <season>");
    expect(missingPointers(["weekly"])[0]!.hint).toContain("Rscript scripts/write_backtest_bundle.R");
  });
});

describe("needsBuild", () => {
  it("builds when there is no build or a source is newer, and not otherwise", () => {
    expect(needsBuild(null, 1)).toBe(true);
    expect(needsBuild(2000, 1000)).toBe(false);
    expect(needsBuild(1000, 2000)).toBe(true);
  });
});
