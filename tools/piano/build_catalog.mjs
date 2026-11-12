// The Piano Follow catalog: tools/piano/catalog.yaml (hand-kept, reviewed) -> catalog/piano/
//   catalog.json  { v: 1, pieces: [{ id, title, composer, arranger, level, pages, size, license, source }] }
//   pieces/<id>.xtscore
// Entries with review: todo are not published: their pages go to dist/piano/review/<id>.png (all
// pages side by side) for the review. review: rejected entries are skipped.
//
//   node tools/piano/build_catalog.mjs --src <PDMX folder> [--yaml tools/piano/catalog.yaml]
//        [--out catalog/piano] [--review dist/piano/review]
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';
import { convert, pack, W, H } from '../../site/tools/piano/convert.mjs';
import { nodeToolkit, nodeRaster, nodeDeflate } from './node_raster.mjs';
import { level as estimate } from './level.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');

// a 1-bit grayscale PNG of the pages, 4 to a row (page bits: 1 = black; PNG: 0 = black)
export function contactSheet(pages, perRow = 4) {
  const cols = Math.min(perRow, pages.length), rows = Math.ceil(pages.length / perRow);
  const w = cols * W + (cols - 1) * 8, h = rows * H + (rows - 1) * 8, stride = Math.ceil(w / 8);
  const raw = Buffer.alloc((stride + 1) * h, 0xff);
  for (let y = 0; y < h; y++) raw[y * (stride + 1)] = 0;                   // filter byte: none
  pages.forEach((p, i) => {
    const ox = (i % perRow) * (W + 8), oy = Math.floor(i / perRow) * (H + 8);
    for (let y = 0; y < H; y++) {
      for (let b = 0; b < W / 8; b++) {
        const v = p[y * (W / 8) + b];
        if (!v) continue;
        for (let k = 0; k < 8; k++) {
          if (v & (0x80 >> k)) {
            const x = ox + b * 8 + k;
            raw[(oy + y) * (stride + 1) + 1 + (x >> 3)] &= ~(0x80 >> (x & 7));
          }
        }
      }
    }
  });
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(td));
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 1; ihdr[9] = 0; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

export async function buildCatalog({ yamlPath, srcDir, outDir, reviewDir, log = () => {} }) {
  const doc = YAML.parse(fs.readFileSync(yamlPath, 'utf8')) || {};
  const entries = doc.pieces || [];
  const ids = new Set();
  for (const e of entries) {
    if (!/^[a-z0-9][a-z0-9-]{0,60}$/.test(e.id || '')) throw new Error(`bad id: ${e.id}`);
    if (ids.has(e.id)) throw new Error(`id twice: ${e.id}`);
    ids.add(e.id);
  }
  const tk = await nodeToolkit();
  fs.mkdirSync(path.join(outDir, 'pieces'), { recursive: true });
  fs.mkdirSync(reviewDir, { recursive: true });
  const built = [], toReview = [], pieces = [], errors = [];
  for (const e of entries) {
    if (e.review === 'rejected') continue;
    const file = path.join(srcDir, e.src);
    const data = file.toLowerCase().endsWith('.mxl') ? new Uint8Array(fs.readFileSync(file)) : fs.readFileSync(file, 'utf8');
    const meta = { title: e.title, composer: e.composer || '', arranger: e.arranger || '', license: e.license || '',
                   source: e.source || 'PDMX (MuseScore)', url: e.url || '' };
    let r;
    try {
      r = await convert(tk, nodeRaster, { name: path.basename(file), data }, meta);
      if (!r.map.onsets.length) throw new Error('no notes');
    } catch (err) {
      log(`error ${e.id}: ${err.message}`);
      errors.push(e.id);
      continue;
    }
    r.header.level = e.level || estimate(r.map);
    if (e.review !== 'ok') {
      fs.writeFileSync(path.join(reviewDir, `${e.id}.png`), contactSheet(r.pages));
      log(`review ${e.id}: ${r.pages.length} pages, ${r.map.onsets.length} onsets, estimated ${r.header.level}`);
      toReview.push(e.id);
      continue;
    }
    const bytes = await pack(r, nodeDeflate);
    fs.writeFileSync(path.join(outDir, 'pieces', `${e.id}.xtscore`), bytes);
    pieces.push({ id: e.id, title: meta.title, composer: meta.composer, arranger: meta.arranger || undefined, level: r.header.level,
                  pages: r.pages.length, size: bytes.length, license: meta.license, source: meta.source });
    built.push(e.id);
    log(`built ${e.id}: ${r.pages.length} pages, ${bytes.length} bytes, ${r.header.level}`);
  }
  // pieces no longer in the list are removed from the published folder
  for (const f of fs.readdirSync(path.join(outDir, 'pieces'))) {
    if (f.endsWith('.xtscore') && !built.includes(f.replace(/\.xtscore$/, ''))) fs.unlinkSync(path.join(outDir, 'pieces', f));
  }
  pieces.sort((a, b) => a.id.localeCompare(b.id));
  fs.writeFileSync(path.join(outDir, 'catalog.json'), JSON.stringify({ v: 1, pieces }, null, 0) + '\n');
  return { built: built.sort(), toReview: toReview.sort(), errors };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
  if (!opt('--src')) { console.error('usage: node build_catalog.mjs --src <PDMX folder> [--yaml F] [--out D] [--review D]'); process.exit(2); }
  const r = await buildCatalog({
    yamlPath: opt('--yaml', path.join(HERE, 'catalog.yaml')), srcDir: opt('--src'),
    outDir: opt('--out', path.join(ROOT, 'catalog', 'piano')), reviewDir: opt('--review', path.join(ROOT, 'dist', 'piano', 'review')),
    log: (s) => console.log(s),
  });
  console.log(`${r.built.length} pieces published, ${r.toReview.length} to review, ${r.errors.length} errors`);
}
