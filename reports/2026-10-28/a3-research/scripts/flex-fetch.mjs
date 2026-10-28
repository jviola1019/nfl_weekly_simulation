// Fetch the "Scheduling changes" section of Wikipedia's "<season> NFL season" pages (keyless API).
// At most one request per 1.2 s, a truthful user agent, a 20 s timeout. Writes <out>/<season>.json
// with { season, page, revid, section_index, wikitext }.
//   node flex-fetch.mjs <out_dir> 2018 2019 ...
import { writeFileSync, mkdirSync } from 'node:fs';
const [out, ...seasons] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
const UA = 'nfl-weekly-simulation/2.9 (research; https://github.com/jviola1019/nfl_weekly_simulation)';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let last = 0;
async function get(params) {
  const wait = last + 1200 - Date.now();
  if (wait > 0) await sleep(wait);
  last = Date.now();
  const url = 'https://en.wikipedia.org/w/api.php?' + new URLSearchParams({ ...params, format: 'json', formatversion: '2' });
  const res = await fetch(url, { headers: { 'User-Agent': UA }, signal: AbortSignal.timeout(20000) });
  if (res.status === 403 || res.status === 429) throw new Error(`HTTP ${res.status}: stopping, never retried`);
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return res.json();
}
for (const season of seasons) {
  const page = `${season}_NFL_season`;
  const secs = await get({ action: 'parse', page, prop: 'sections|revid' });
  const sec = secs.parse.sections.find((s) => /^Schedul(ing|e) changes$/i.test(s.line.trim()));
  if (!sec) { console.log(`${season}: no "Scheduling changes" section`); continue; }
  const w = await get({ action: 'parse', page, section: sec.index, prop: 'wikitext|revid' });
  writeFileSync(`${out}/${season}.json`, JSON.stringify({ season: Number(season), page, revid: w.parse.revid,
    section_index: sec.index, wikitext: w.parse.wikitext }, null, 1));
  console.log(`${season}: revid ${w.parse.revid}, section ${sec.index} (${sec.line}), ${w.parse.wikitext.length} chars`);
}
