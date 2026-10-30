// apps/dict/stardict2shards.py in JavaScript: a StarDict dictionary (.ifo + .idx + .dict or
// .dict.dz) -> the shard files the Dictionary mini app reads. Same rules and the same output as the
// Python script; the tests compare the two.
//
//   const set = await gatherFiles([{ name, bytes }])   archives (.zip, .tar, .tar.gz, .tgz, .tar.zst) unpacked
//   const dicts = findDictionaries(set)                 [{ ifo, base, info }]
//   const r = await shard(dict, set, { prefix, shardKb, maxDef }, log)   -> { files, words, shards }

import { readZip, untar, gunzip } from '../../assets/zip.js';
import { unescapeHtml } from '../../assets/unescape.js';

const dec = new TextDecoder('utf-8');

export async function gatherFiles(files, zstd) {
  const out = new Map();
  for (const f of files) {
    const n = f.name.toLowerCase();
    if (n.endsWith('.zip')) for (const x of await readZip(f.bytes)) out.set(x.name, x.bytes);
    else if (n.endsWith('.tar.gz') || n.endsWith('.tgz')) for (const x of untar(await gunzip(f.bytes))) out.set(x.name, x.bytes);
    else if (n.endsWith('.tar.zst') || n.endsWith('.tzst')) {
      if (!zstd) throw new Error('.tar.zst needs zstd, which did not load');
      for (const x of untar(await zstd(f.bytes))) out.set(x.name, x.bytes);
    } else if (n.endsWith('.tar')) for (const x of untar(f.bytes)) out.set(x.name, x.bytes);
    else if (n.endsWith('.tar.bz2') || n.endsWith('.tbz2') || n.endsWith('.tar.xz') || n.endsWith('.7z') || n.endsWith('.rar')) {
      throw new Error(`${f.name}: unpack this archive first and add the files inside`);
    } else out.set(f.name, f.bytes);
  }
  return out;
}

export function readIfo(bytes) {
  const info = {};
  for (const line of dec.decode(bytes).split('\n')) {
    const i = line.indexOf('=');
    if (i >= 0) info[line.slice(0, i).trim()] = line.slice(i + 1).replace(/\r$/, '').trim();
  }
  return info;
}

export function findDictionaries(set) {
  const out = [];
  for (const [name, bytes] of set) {
    if (!name.toLowerCase().endsWith('.ifo')) continue;
    out.push({ ifo: name, base: name.slice(0, -4), info: readIfo(bytes) });
  }
  return out.sort((a, b) => a.ifo.localeCompare(b.ifo));
}

function* iterIdx(data, bits) {
  const dv = new DataView(data.buffer, data.byteOffset, data.byteLength);
  let i = 0;
  const n = data.length;
  while (i < n) {
    let j = data.indexOf(0, i);
    if (j < 0) j = n;
    const word = dec.decode(data.subarray(i, j));
    let off, size;
    if (bits === 64) { off = Number(dv.getBigUint64(j + 1)); size = dv.getUint32(j + 9); i = j + 13; }
    else { off = dv.getUint32(j + 1); size = dv.getUint32(j + 5); i = j + 9; }
    yield [word, off, size];
  }
}

export function htmlToText(s) {
  s = s.replace(/<\/(p|div|li|h[1-6]|blockquote|tr|dd|dt)\s*>|<br\s*\/?>/gi, '\n');
  s = s.replace(/<(li)\b[^>]*>/gi, '• ');
  s = s.replace(/<[^>]+>/g, '');
  s = unescapeHtml(s).replace(/ /g, ' ');
  s = s.replace(/[ \t]+/g, ' ');
  s = s.replace(/ *\n+ */g, '\n');
  return s.trim();
}

const POS = '(?:n|v|adj|adv|prep|pron|conj|interj)';
const SENSE = new RegExp(` (?=${POS} (?:\\d+)?: )|(?<=[^\\d ]) +(?=\\d+: )`, 'g');

// dictd-style plain text: the headword repeated on the first line, then hard-wrapped lines with
// deep indentation. Unwrap, drop the repeated headword, one sense per line.
export function plainText(s, word = '') {
  let lines = s.replace(/\r/g, '').split('\n').map((l) => l.replace(/\s+$/u, ''));
  if (lines.length && lines[0].trim().toLowerCase() === word.trim().toLowerCase()) lines = lines.slice(1);
  let t = lines.filter((l) => l.trim()).map((l) => l.trim()).join(' ');
  t = t.replace(/ {2,}/g, '  ');
  t = t.replace(SENSE, '\n');
  t = t.replace(/(?<=\]) (?=\d+: )|(?<=\]) (?=[a-z]+ \d+: )/g, '\n');
  t = t.replace(new RegExp(`(^|\\n)(${POS})\\n(\\d+: )`, 'g'), '$1$2 $3');
  return t.trim();
}

function definitionText(raw, types, word) {
  if (types) {
    if (types === 'h') return htmlToText(dec.decode(raw));
    return plainText(dec.decode(raw), word);
  }
  const out = [];
  let i = 0;
  while (i < raw.length) {
    const t = String.fromCharCode(raw[i]); i++;
    if (t >= 'a' && t <= 'z') {
      let j = raw.indexOf(0, i);
      if (j === -1) j = raw.length;
      const part = raw.subarray(i, j); i = j + 1;
      out.push('hg'.includes(t) ? htmlToText(dec.decode(part)) : dec.decode(part).trim());
    } else {
      const size = new DataView(raw.buffer, raw.byteOffset + i, 4).getUint32(0); i += 4;
      i += size;                         // binary parts (images, sounds) are skipped
    }
  }
  return out.filter(Boolean).join('\n');
}

const cpLen = (s) => { let n = 0; for (const _ of s) n++; return n; };
const enc = new TextEncoder();

// opts: { prefix, shardKb = 200, maxDef = 1500 }
export async function shard(dict, set, opts = {}, log = () => {}) {
  const prefix = opts.prefix || '';
  if (prefix && !/^[A-Za-z0-9]+$/.test(prefix)) throw new Error('prefix: letters and digits only');
  const shardKb = opts.shardKb || 200, maxDef = opts.maxDef || 1500;
  const info = dict.info;
  const types = info.sametypesequence || '';
  const bits = info.idxoffsetbits === '64' ? 64 : 32;
  const find = (suffix) => set.get(dict.base + suffix) ?? null;
  let idx = find('.idx');
  if (!idx && find('.idx.gz')) idx = await gunzip(find('.idx.gz'));
  if (!idx) throw new Error(`${dict.base}.idx is missing`);
  let blob = find('.dict');
  if (!blob && find('.dict.dz')) blob = await gunzip(find('.dict.dz'));
  if (!blob) throw new Error(`${dict.base}.dict or .dict.dz is missing`);
  log(`${info.bookname || dict.base}: ${info.wordcount} words, types=${types || 'mixed'}`);

  const pre = prefix ? prefix + '_' : '';
  const files = [], shards = [];
  let cur = [], curSize = 0, first = null, count = 0, lastWord = null;
  const limit = shardKb * 1024;
  const flush = () => {
    if (!cur.length) return;
    const name = `${pre}d${String(shards.length).padStart(3, '0')}.txt`;
    files.push({ name, data: cur.join('\n') + '\n' });
    shards.push([name, first, cur[cur.length - 1].split('\t', 1)[0]]);
    cur = []; curSize = 0; first = null;
  };
  let k = 0;
  for (let [word, off, size] of iterIdx(idx, bits)) {
    if (++k % 20000 === 0) { log(`${k} entries read`); await new Promise((r) => setTimeout(r, 0)); }
    let text = definitionText(blob.subarray(off, off + size), types, word);
    if (cpLen(text) > maxDef) {
      const head = [...text].slice(0, maxDef).join('');
      const sp = head.lastIndexOf(' ');
      text = (sp >= 0 ? head.slice(0, sp) : head) + ' …';
    }
    word = word.replace(/\t/g, ' ').replace(/\n/g, ' ').trim();
    if (!word || !text) continue;
    const line = word + '\t' + text.replace(/\\/g, '\\\\').replace(/\n/g, '\\n');
    if (word === lastWord && cur.length) {
      // the same headword again: joined to the previous line
      cur[cur.length - 1] += '\\n' + line.slice(line.indexOf('\t') + 1);
      continue;
    }
    if (curSize + cpLen(line) + 1 > limit && cur.length) flush();
    if (first === null) first = word;
    cur.push(line); curSize += enc.encode(line).length + 1;
    lastWord = word; count++;
  }
  flush();
  files.push({ name: pre + 'shards.tsv', data: shards.map(([n, lo, hi]) => `${n}\t${lo}\t${hi}\n`).join('') });
  files.push({ name: pre + 'info.txt', data: `name=${info.bookname || dict.base.replace(/^.*[\\/]/, '')}\nwords=${count}\nshards=${shards.length}\n` });
  if (shards.length > 500) log('More than 500 shards: the app\'s folder holds 512 files. Raise the shard size.');
  return { files, words: count, shards: shards.length };
}
