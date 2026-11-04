// Normalize the "Scheduling changes" wikitext into one row per bullet:
// season, week, teams (from the season links), the text without markup, an explicit
// "On <Month> <day>" announcement date if the text has one, and the earliest citation access-date.
//   node flex-bullets.mjs <raw_dir> <out_json>
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
const [raw, out] = process.argv.slice(2);
const MONTHS = 'January|February|March|April|May|June|July|August|September|October|November|December';
const rows = [];
for (const f of readdirSync(raw).filter((x) => /^\d{4}\.json$/.test(x)).sort()) {
  const { season, revid, wikitext } = JSON.parse(readFileSync(`${raw}/${f}`, 'utf8'));
  // named references are defined once and reused; collect their access dates
  const named = {};
  for (const m of wikitext.matchAll(/<ref name="?([^">]+)"?>([\s\S]*?)<\/ref>/g)) {
    const d = m[2].match(/access-date\s*=\s*([^|}]+)/);
    if (d) named[m[1]] = d[1].trim();
  }
  let week = null;
  for (let line of wikitext.split('\n')) {
    // a week header may stand alone ('''Week 6:'''), open a bullet (* '''Week 7:''' The ...),
    // or head sub-bullets (*'''Week 4:''' then ** or :* lines); 2018-2024 use all three
    const wk = line.match(/^[*:\s]*'''Weeks? (\d+)[^']*'''\s*:?\s*(.*)$/);
    if (wk) {
      week = Number(wk[1]);
      if (!wk[2].trim()) continue;
      line = '* ' + wk[2];
    }
    if (!/^[*:]/.test(line) || week === null) continue;
    if (!line.replace(/^[*:\s]+/, '').trim()) continue;
    const teams = [...line.matchAll(/\[\[\d{4} ([A-Z][A-Za-z.' ]+?) season\|/g)].map((m) => m[1]);
    const dates = [...line.matchAll(/access-date\s*=\s*([^|}]+)/g)].map((m) => m[1].trim());
    for (const m of line.matchAll(/<ref name="?([^">/]+)"?\s*\/>/g)) if (named[m[1]]) dates.push(named[m[1]]);
    const explicit = line.match(new RegExp(`\\bOn (${MONTHS}) (\\d{1,2})(?:, (\\d{4}))?`));
    const text = line.replace(/<ref[\s\S]*?(<\/ref>|\/>)/g, '').replace(/\{\{[\s\S]*?\}\}/g, '')
      .replace(/\[\[(?:[^|\]]*\|)?([^\]]+)\]\]/g, '$1').replace(/&nbsp;/g, ' ').replace(/'''?/g, '').replace(/^[*:\s]+/, '').trim();
    rows.push({ season, revid, week, teams, explicit_date: explicit ? `${explicit[1]} ${explicit[2]}${explicit[3] ? ', ' + explicit[3] : ''}` : null,
      cite_dates: [...new Set(dates)], text });
  }
}
writeFileSync(out, JSON.stringify(rows, null, 1));
console.log(`${rows.length} bullets; by season: ${JSON.stringify(rows.reduce((a, r) => (a[r.season] = (a[r.season] || 0) + 1, a), {}))}`);
