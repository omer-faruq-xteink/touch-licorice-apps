// The web converters on the command line, for test_converters.py (Node 24: node:sqlite, zlib zstd).
//   node node_cli.mjs anki DECK OUT_DIR [--update] [--reverse] [--front F] [--back B] [--name N] [--prefix P]
//   node node_cli.mjs stardict SRC_DIR_OR_ARCHIVE OUT_DIR [--prefix P] [--shard-kb N] [--max-def N]
import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync, statSync, mkdtempSync, rmSync } from 'node:fs';
import { join, basename } from 'node:path';
import { tmpdir } from 'node:os';
import { zstdDecompressSync } from 'node:zlib';
import { DatabaseSync } from 'node:sqlite';
import { readDeck, makeFiles } from '../tools/anki/anki.js';
import { gatherFiles, findDictionaries, shard } from '../tools/dictionary/stardict.js';

const [, , what, src, out, ...rest] = process.argv;
const opt = (n) => { const i = rest.indexOf(n); return i >= 0 ? rest[i + 1] : undefined; };
const flag = (n) => rest.includes(n);
mkdirSync(out, { recursive: true });

function openDb(bytes) {
  const dir = mkdtempSync(join(tmpdir(), 'apkg-'));
  const path = join(dir, 'c.db');
  writeFileSync(path, bytes);
  const db = new DatabaseSync(path, { readOnly: true });
  return {
    all: (sql) => db.prepare(sql).all().map((r) => Object.values(r)),
    close: () => { db.close(); rmSync(dir, { recursive: true, force: true }); },
  };
}

if (what === 'anki') {
  const notes = await readDeck(basename(src), new Uint8Array(readFileSync(src)), { openDb, zstd: (b) => new Uint8Array(zstdDecompressSync(b)) });
  const old = new Map();
  if (flag('--update')) for (const f of readdirSync(out)) old.set(f, readFileSync(join(out, f), 'utf8'));
  const r = makeFiles(basename(src), notes, { name: opt('--name'), prefix: opt('--prefix'), front: opt('--front'), back: opt('--back'),
    reverse: flag('--reverse'), update: flag('--update'), maxChars: opt('--max-chars') && +opt('--max-chars'), built: 'X' }, old);
  for (const f of readdirSync(out)) if (new RegExp(`^${r.prefix}_c\\d{3}\\.txt$`).test(f)) rmSync(join(out, f));
  for (const f of r.files) writeFileSync(join(out, f.name), f.data);
  console.log(`${r.name}: ${r.cards} cards in ${r.shards} files, prefix ${r.prefix}`);
} else if (what === 'stardict') {
  const list = [];
  const add = (p) => { if (statSync(p).isDirectory()) for (const f of readdirSync(p)) add(join(p, f)); else list.push({ name: p.replace(/\\/g, '/'), bytes: new Uint8Array(readFileSync(p)) }); };
  add(src);
  const set = await gatherFiles(list, (b) => new Uint8Array(zstdDecompressSync(b)));
  const d = findDictionaries(set)[0];
  const r = await shard(d, set, { prefix: opt('--prefix'), shardKb: opt('--shard-kb') && +opt('--shard-kb'), maxDef: opt('--max-def') && +opt('--max-def') });
  for (const f of r.files) writeFileSync(join(out, f.name), f.data);
  console.log(`${r.words} entries -> ${r.shards} shards`);
}
