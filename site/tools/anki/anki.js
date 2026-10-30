// apps/anki/apkg2cards.py in JavaScript: an Anki deck (.apkg) or a word list (.tsv / .csv / .txt)
// -> the card files the Anki mini app reads. Same rules and the same output as the Python script;
// the tests compare the two.
//
//   const notes = await readDeck(fileName, bytes, { openDb, zstd })
//   fieldsSummary(notes)                          the note types, fields and the default front / back
//   makeFiles(fileName, notes, opts, oldFiles)    -> { files: [{ name, data }], name, prefix, cards, ... }
//
// openDb(bytes) -> { all(sql) -> rows as arrays, close() }  (sql.js in the browser, node:sqlite in tests)
// zstd(bytes) -> bytes, for newer Anki exports (collection.anki21b)

import { readZip } from '../../assets/zip.js';
import { unescapeHtml } from '../../assets/unescape.js';

export const MAX_SHARDS = 300;
const NAME_RE = /[^A-Za-z0-9]+/g;

// ------------------------------------------------------------------ text

const len = (s) => [...s].length;
const rstrip = (s) => s.replace(/\s+$/u, '');

export function clean(s) {
  s = s.replace(/<(style|script)\b[\s\S]*?<\/\1>/gi, '');
  s = s.replace(/<br\s*\/?>|<\/(div|p|li|tr|h\d)>/gi, '\n');
  s = s.replace(/<li\b[^>]*>/gi, '- ');
  s = s.replace(/<[^>]+>/g, '');
  s = s.replace(/\[sound:[^\]]*\]/g, '');
  s = unescapeHtml(s).replace(/ /g, ' ');
  const lines = s.split('\n').map((l) => l.replace(/[ \t]+/g, ' ').trim());
  const out = [];
  for (const l of lines) if (l || (out.length && out[out.length - 1])) out.push(l);
  return out.join('\n').trim();
}

const CLOZE = /\{\{c\d+::([\s\S]*?)(?:::([\s\S]*?))?\}\}/g;
const hasCloze = (s) => /\{\{c\d+::([\s\S]*?)(?:::([\s\S]*?))?\}\}/.test(s);

function cloze(s) {
  const front = s.replace(CLOZE, (m, a, hint) => '[' + (hint === undefined || hint === '' ? '...' : hint) + ']');
  const back = s.replace(CLOZE, (m, a) => a);
  return [front, back];
}

function cut(s, n) {
  const cs = [...s];
  return cs.length <= n ? s : rstrip(cs.slice(0, n - 1).join('')) + '…';
}

const esc = (s) => s.replace(/\\/g, '\\\\').replace(/\t/g, ' ').replace(/\r/g, '').replace(/\n/g, '\\n');

// ------------------------------------------------------------------ reading decks

async function openCollection(bytes, env) {
  const files = await readZip(bytes);
  let col = null;
  for (const n of ['collection.anki21b', 'collection.anki21', 'collection.anki2']) {
    col = files.find((f) => f.name === n);
    if (col) break;
  }
  if (!col) throw new Error('no Anki collection inside this file');
  let raw = col.bytes;
  if (col.name.endsWith('21b')) {
    if (!env.zstd) throw new Error('this is a newer Anki export (collection.anki21b) and zstd is not available');
    raw = await env.zstd(raw);
  }
  return env.openDb(raw);
}

function noteTypes(db) {
  try {
    const rows = db.all('select models from col');
    const models = JSON.parse((rows[0] && rows[0][0]) || '{}');
    if (models && Object.keys(models).length) {
      const out = new Map();
      for (const [k, m] of Object.entries(models)) {
        out.set(String(parseInt(k, 10)), [m.name, [...m.flds].sort((a, b) => a.ord - b.ord).map((f) => f.name)]);
      }
      return out;
    }
  } catch { /* the newer layout below */ }
  const out = new Map();
  for (const [ntid, name] of db.all('select id, name from notetypes')) {
    const flds = db.all(`select name from fields where ntid = ${Number(ntid)} order by ord`).map((r) => r[0]);
    out.set(String(ntid), [name, flds]);
  }
  return out;
}

async function readApkg(bytes, env) {
  const db = await openCollection(bytes, env);
  let types, rows;
  try {
    types = noteTypes(db);
    rows = db.all('select n.id, n.mid, n.flds from notes n join (select nid, min(type) t, min(due) d ' +
      'from cards group by nid) c on c.nid = n.id order by c.t, c.d, n.id');
  } finally {
    db.close();
  }
  const notes = [];
  for (const [nid, mid, flds] of rows) {
    const [name, fn0] = types.get(String(mid)) || ['?', []];
    const vals = String(flds).split('\x1f');
    const fnames = [...fn0];
    for (let k = fn0.length; k < vals.length; k++) fnames.push(`Field ${k + 1}`);
    const fields = {};
    vals.forEach((v, k) => { fields[fnames[k]] = clean(v); });
    notes.push([String(nid), fields, name, fnames.slice(0, vals.length)]);
  }
  return notes;
}

// Python's csv.reader (excel dialect) with the given delimiter, on text read with newline=''
function csvRows(text, delim) {
  const rows = [];
  let row = [], field = '', i = 0, quoted = false, inQuotes = false, started = false;
  const endField = () => { row.push(field); field = ''; quoted = false; started = false; };
  const endRow = () => { endField(); rows.push(row); row = []; };
  while (i < text.length) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i += 2; continue; }
        inQuotes = false; i++; continue;
      }
      field += c; i++; continue;
    }
    if (c === delim) { endField(); i++; continue; }
    if (c === '\r' || c === '\n') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      i++;
      if (!started && row.length === 0 && field === '') { rows.push([]); continue; }
      endRow(); continue;
    }
    if (c === '"' && !started) { inQuotes = true; quoted = true; started = true; i++; continue; }
    field += c; started = true; i++;
  }
  if (started || row.length || field || inQuotes) endRow();
  return rows;
}

function readList(fileName, bytes) {
  let text = new TextDecoder('utf-8').decode(bytes);
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const delim = fileName.toLowerCase().endsWith('.csv') ? ',' : '\t';
  const out = [];
  csvRows(text, delim).forEach((row, k) => {
    if (!row.length || !row[0].trim() || row[0].startsWith('#')) return;
    out.push([`L${k + 1}`, { Front: clean(row[0]), Back: clean(row.slice(1).join(' / ')) }, 'list', ['Front', 'Back']]);
  });
  return out;
}

export const isList = (fileName) => /\.(tsv|csv|txt)$/i.test(fileName);

export async function readDeck(fileName, bytes, env) {
  return isList(fileName) ? readList(fileName, bytes) : readApkg(bytes, env);
}

// ------------------------------------------------------------------ cards

// per note type, its fields in order that hold text (not empty, not just a number) in at least
// 80 % of its notes: the first is the default front, the rest the default back
export function usefulFields(notes) {
  const stats = new Map();
  for (const [, fields, model, order] of notes) {
    if (!stats.has(model)) stats.set(model, { n: 0, order, ok: new Map() });
    const st = stats.get(model);
    st.n++;
    for (const f of order) {
      const v = fields[f] || '';
      if (v && !/^[\d\s.,:#_/-]*$/u.test(v)) st.ok.set(f, (st.ok.get(f) || 0) + 1);
    }
  }
  const out = new Map();
  for (const [m, st] of stats) {
    const good = st.order.filter((f) => (st.ok.get(f) || 0) >= 0.8 * st.n);
    out.set(m, good.length ? good : st.order);
  }
  return out;
}

// what --list-fields prints: [{ model, notes, fields: [{ name, role, sample }] }]
export function fieldsSummary(notes) {
  const useful = usefulFields(notes), seen = new Set(), out = [];
  for (const [, fields, model, order] of notes) {
    if (seen.has(model)) continue;
    seen.add(model);
    const good = useful.get(model);
    out.push({
      model, notes: notes.filter((n) => n[2] === model).length,
      fields: order.map((f) => ({ name: f, role: f === good[0] ? 'front' : good.includes(f) ? 'back' : '', sample: cut((fields[f] || '').replace(/\n/g, ' / '), 70) })),
    });
  }
  return out;
}

export function makeCards(notes, o) {
  const useful = usefulFields(notes), cards = [];
  for (const [nid, fields, model] of notes) {
    const good = useful.get(model);
    const frontF = o.front && o.front in fields ? o.front : good[0];
    const backFs = o.back ? o.back.split(',').filter((f) => f in fields) : good.filter((f) => f !== frontF);
    let front = fields[frontF] || '';
    let back = backFs.filter((f) => fields[f]).map((f) => fields[f]).join('\n');
    if (hasCloze(front)) {
      const [fr, filled] = cloze(front);
      front = fr;
      back = filled + (back ? '\n' + back : '');
    }
    if (!front || !back) continue;
    front = cut(front, o.maxChars || 800);
    back = cut(back, o.maxChars || 800);
    cards.push([nid, front, back]);
    if (o.reverse) cards.push([nid + 'r', back, front]);
  }
  return cards;
}

function pyTitle(s) {
  let out = '', prev = false;
  for (const ch of s) {
    const cased = ch.toLowerCase() !== ch.toUpperCase();
    out += cased ? (prev ? ch.toLowerCase() : ch.toUpperCase()) : ch;
    prev = cased;
  }
  return out;
}

export function deckNames(fileName, o = {}) {
  const base = fileName.replace(/^.*[\\/]/, '').replace(/\.[^.]*$/, '').replace(/[_\s]+\d{6,}$/u, '');
  const name = o.name || base.replace(/[_\s]+/gu, ' ').trim();
  const prefix = o.prefix || (pyTitle(name).replace(NAME_RE, '').slice(0, 16) || 'deck');
  if (!/^[A-Za-z0-9]{1,24}$/.test(prefix) || ['my', 'en'].includes(prefix.toLowerCase())) {
    throw new Error(`prefix: 1..24 letters or digits, not "my" or "en" (the app uses those); got "${prefix}"`);
  }
  return { name, prefix };
}

// the previous files of the deck (for an update): ids in their old places, and the old shard size
function readOld(oldFiles, prefix) {
  const get = (n) => oldFiles && oldFiles.get(n);
  const info = get(`${prefix}_info.txt`);
  if (info === undefined || info === null) return [[], null];
  let per = null;
  for (const line of info.split('\n')) if (line.startsWith('per=')) per = parseInt(line.slice(4), 10);
  const ids = [];
  for (let s = 0; get(`${prefix}_c${String(s).padStart(3, '0')}.txt`) != null; s++) {
    const t = get(`${prefix}_c${String(s).padStart(3, '0')}.txt`);
    const lines = t.split('\n');
    if (lines[lines.length - 1] === '') lines.pop();
    for (const line of lines) ids.push(line.split('\t', 1)[0]);
  }
  return [ids, per];
}

const pad = (n) => String(n).padStart(2, '0');
function stamp(d = new Date()) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// o: { name, prefix, front, back, reverse, maxChars, update }; oldFiles: Map name -> text
export function makeFiles(fileName, notes, o = {}, oldFiles = null) {
  const { name, prefix } = deckNames(fileName, o);
  const cards = makeCards(notes, o);
  if (!cards.length) throw new Error('no cards: pick other fields for the front and the back');
  const [oldIds, oldPer] = o.update ? readOld(oldFiles, prefix) : [[], null];
  let slots, per;
  if (oldIds.length) {
    const byId = new Map(cards.map((c) => [c[0], c]));
    slots = oldIds.map((i) => { const c = byId.get(i); byId.delete(i); return c || [i, '', '']; });
    for (const c of cards) if (byId.has(c[0])) slots.push(c);
    per = oldPer;
  } else {
    slots = cards;
    per = Math.max(100, Math.ceil(cards.length / MAX_SHARDS));
  }
  const shards = Math.ceil(slots.length / per);
  if (shards > MAX_SHARDS) {
    throw new Error(`${slots.length} cards make ${shards} files, more than the app can hold (${MAX_SHARDS}); convert without updating, or split the deck`);
  }
  const files = [];
  for (let s = 0; s < shards; s++) {
    const body = slots.slice(s * per, (s + 1) * per).map(([cid, f, b]) => `${esc(cid)}\t${esc(f)}\t${esc(b)}\n`).join('');
    files.push({ name: `${prefix}_c${String(s).padStart(3, '0')}.txt`, data: body });
  }
  const live = slots.filter((c) => c[1]).length;
  const source = fileName.replace(/^.*[\\/]/, '');
  files.push({ name: `${prefix}_info.txt`, data: `name=${name}\ncards=${live}\nshards=${shards}\nper=${per}\nsource=${source}\nbuilt=${o.built || stamp()}\n` });
  const removed = oldIds.length ? slots.slice(0, oldIds.length).filter((c) => !c[1]).length : 0;
  return {
    files, name, prefix, cards: live, shards,
    update: oldIds.length ? { kept: oldIds.length - removed, removed, added: slots.length - oldIds.length } : null,
  };
}
