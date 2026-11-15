// The Offline Map tool's pure parts (site/tools/offlinemap/): name folding, the 1-bit BMP and zlib
// writer, the pack writer read back by a port of the app's reader, tile math and estimates, the
// polite tile fetcher, and the two schemas.   node site/test/test_offlinemap.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { fold } from '../tools/offlinemap/fold.js';
import { bmp1, zlib, isBlank } from '../tools/offlinemap/bmpz.js';
import { writePack } from '../tools/offlinemap/pack.js';
import { readPack, unzlib } from './mapread.mjs';
import { lengthM, bboxWithMargin, toGpx, parseGpx, streetLabels } from '../tools/offlinemap/route.js';
import { metatiles, toBits, cut } from '../tools/offlinemap/render.js';
import { ROLES, symbolImage, patternImage } from '../tools/offlinemap/eink.js';
import * as shortbread from '../tools/offlinemap/schema/shortbread.js';
import * as openmaptiles from '../tools/offlinemap/schema/openmaptiles.js';
import { SOURCES, pickSource } from '../tools/offlinemap/sources.js';
import { TileFetcher } from '../tools/offlinemap/fetcher.js';
import { lonLatToTile, tileRange, PRESETS, vectorZoom, vectorTiles, estimate, MAX_TILES } from '../tools/offlinemap/tiles.js';

const HERE = dirname(fileURLToPath(import.meta.url));
let bad = 0, n = 0;
function check(name, ok, info = '') {
  n++;
  if (ok) console.log('ok   ', name);
  else { bad++; console.log('FAIL ', name, info); }
}
const eq = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

// ---------------------------------------------------------------- folding (shared with the app)
const rows = readFileSync(join(HERE, 'fixtures', 'fold_words.tsv'), 'utf8').split('\n').filter((l) => l && !l.startsWith('#'));
check('fold word list has at least 120 rows', rows.length >= 120, rows.length);
let foldBad = [];
for (const r of rows) {
  const [inp, want] = r.split('\t');
  if (fold(inp) !== want) foldBad.push(`${inp} -> ${fold(inp)} (want ${want})`);
}
check('fold matches every row', foldBad.length === 0, foldBad.slice(0, 5).join('; '));

// ---------------------------------------------------------------- BMP + zlib
const white = new Uint8Array(256 * 256);
const b = bmp1(white);
const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
check('bmp1: 8254 bytes, BM, 256x256, 1 bpp', b.length === 8254 && b[0] === 0x42 && b[1] === 0x4d &&
  dv.getInt32(18, true) === 256 && dv.getInt32(22, true) === 256 && dv.getUint16(28, true) === 1);
check('bmp1: palette black then white', eq([...b.subarray(54, 62)], [0, 0, 0, 0, 255, 255, 255, 0]));
check('isBlank(all white)', isBlank(white));
const dot = new Uint8Array(256 * 256); dot[0] = 1;
check('isBlank(one black pixel) is false', !isBlank(dot));
const bd = bmp1(dot);
// the top-left pixel is in the last row (bottom-up), first bit; 0 = black
check('bmp1: top-left black pixel lands in the last row', (bd[62 + 255 * 32] & 0x80) === 0 && (bd[62 + 255 * 32 + 1]) === 0xff);
const z = await zlib(b);
check('zlib: zlib header and round trip', z[0] === 0x78 && eq([...await unzlib(z)], [...b]));

// ---------------------------------------------------------------- pack v1
const t1 = await zlib(bmp1(dot));
const t2 = await zlib(bmp1(white.map((_, i) => (i % 7 === 0 ? 1 : 0))));
const meta = { name: 'Test', bounds: [29, 40.9, 29.1, 41], levels: [15, 16], lang: 'local', made: '2026-11-15',
  data_date: '2026-10-19', source: 'versatiles', attribution: '© OpenStreetMap contributors, VersaTiles', tool: 1 };
const names = [
  { name: 'Kadıköy', kind: 4, lon: 29.0275, lat: 40.9903 },
  { name: 'Moda Caddesi', kind: 6, lon: 29.026, lat: 40.984 },
  { name: 'Haydarpaşa', kind: 7, lon: 29.019, lat: 40.997 },
];
const pack = writePack({
  meta,
  levels: [
    { z: 15, x0: 19026, y0: 12278, nx: 2, ny: 2, tiles: [t1, null, t2, t1] },
    { z: 16, x0: 38052, y0: 24556, nx: 1, ny: 2, tiles: [null, t2] },
  ],
  names,
});
const r = readPack(pack);
check('pack: magic and version', r.header.magic === 'XTMAP1\0\0' && r.header.version === 1 && r.header.format === 2 && r.header.tileSize === 256);
check('pack: meta round trip', JSON.stringify(r.meta) === JSON.stringify(meta));
check('pack: levels', r.levels.length === 2 && r.levels[0].z === 15 && r.levels[1].ny === 2);
check('pack: a tile reads back byte-equal', eq([...r.tile(15, 19026, 12278)], [...t1]) && eq([...r.tile(16, 38052, 24557)], [...t2]));
check('pack: an empty tile reads back null', r.tile(15, 19027, 12278) === null && r.tile(16, 38052, 24556) === null);
check('pack: outside the range is null', r.tile(15, 19030, 12278) === null && r.tile(14, 0, 0) === null);
const k = r.search('kad', 10);
check('pack: search finds Kadıköy', k.length === 1 && k[0].name === 'Kadıköy' && k[0].kind === 4 &&
  k[0].lon7 === Math.round(29.0275 * 1e7) && k[0].lat7 === Math.round(40.9903 * 1e7), JSON.stringify(k));
check('pack: search folds the query', r.search('HAYDARPAŞA', 5).length === 1);
check('pack: no match is empty', r.search('zzz', 5).length === 0);

// many names: several blocks, first and last still found; a long name is cut on a character boundary
const many = [];
for (let i = 0; i < 3000; i++) many.push({ name: `Street ${String(i).padStart(4, '0')}`, kind: 6, lon: 29 + i / 1e5, lat: 41 });
many.push({ name: 'ş'.repeat(150), kind: 11, lon: 29, lat: 41 });            // 300 bytes of UTF-8
const p2 = writePack({ meta, levels: [{ z: 15, x0: 0, y0: 0, nx: 1, ny: 1, tiles: [null] }], names: many });
const r2 = readPack(p2);
check('names: several blocks', r2.nameBlocks > 1, r2.nameBlocks);
check('names: the first and the last found', r2.search('street 0000', 3)[0]?.name === 'Street 0000' && r2.search('street 2999', 3)[0]?.name === 'Street 2999');
const long = r2.search('sss', 1)[0];
const lb = long ? new TextEncoder().encode(long.name) : new Uint8Array(999);
check('names: a 300-byte name cut to <= 255 bytes, valid UTF-8', lb.length <= 255 && !long.name.includes('�'), lb.length);

// ---------------------------------------------------------------- tiles, presets, estimate
const BOX = [29.0, 40.95, 29.1, 41.03];
const rg = tileRange(BOX, 16);
check('tileRange matches the spike reference', rg.x0 === 38047 && rg.y0 === 24563 && rg.nx === 19 && rg.ny === 21, JSON.stringify(rg));
const lt = lonLatToTile(29.0, 41.03, 16);
check('lonLatToTile gives floats', Math.floor(lt.x) === 38047 && Math.floor(lt.y) === 24563 && lt.x % 1 !== 0);
check('presets', eq(PRESETS.overview, [8, 9, 10, 11, 12, 13]) && eq(PRESETS.streets, [10, 11, 12, 13, 14, 15, 16, 17]) &&
  PRESETS.closeup[0] === 10 && PRESETS.closeup.at(-1) === 19 && PRESETS.closeup.length === 10);
check('vectorZoom = min(z-1, 14)', vectorZoom(10) === 9 && vectorZoom(15) === 14 && vectorZoom(19) === 14);
const VT = { maxVectorTiles: 10000, parallel: 4 };
const OFM = { maxVectorTiles: 3000, maxBytes: 50e6, parallel: 4 };
const est = estimate(BOX, PRESETS.streets, VT);
const sumTiles = PRESETS.streets.reduce((s, z) => { const q = tileRange(BOX, z); return s + q.nx * q.ny; }, 0);
check('estimate: tiles is the exact sum', est.tiles === sumTiles, `${est.tiles} vs ${sumTiles}`);
const perHigh = (z) => (z <= 16 ? 5 : z === 17 ? 3.5 : z === 18 ? 2.5 : 2) * 1024;   // measured on Kadikoy, 2026-11-15
const hi = PRESETS.streets.reduce((s, z) => { const q = tileRange(BOX, z); return s + q.nx * q.ny * perHigh(z); }, 0);
check('estimate: byte range', Math.round(est.bytesLow) === Math.round(sumTiles * 0.6 * 1024) && Math.round(est.bytesHigh) === Math.round(hi));
let vt = 0;
for (const vz of new Set(PRESETS.streets.map(vectorZoom))) { const q = tileRange(BOX, vz); vt += (q.nx + 2) * (q.ny + 2); }
check('vectorTiles: (nx+2)(ny+2) per distinct vector zoom', vectorTiles(BOX, PRESETS.streets) === vt && est.vectorTiles === vt);
check('estimate: a city is accepted', est.refused === null && est.seconds > 0);
check('estimate: refuses when 1.25 x the vector tiles passes the limit (MapLibre fetches margins)', estimate(BOX, PRESETS.streets, { maxVectorTiles: Math.ceil(vt * 1.2), parallel: 4 }).refused === 'vector-tiles');
const tr = estimate([26, 38, 32, 41], PRESETS.overview, OFM);
check('estimate: a region at Overview is refused for vector tiles under 3000', tr.refused === 'vector-tiles' && /smaller area/i.test(tr.advice) && /Overview/.test(tr.advice), tr.advice);
const tk = estimate([26, 36, 45, 42], PRESETS.streets, VT);
check('estimate: Turkey at Streets is refused', tk.refused === 'tiles' && /Overview/.test(tk.advice), tk.advice);
check('estimate: over MAX_TILES output tiles is refused (the browser holds the pack in memory)', MAX_TILES === 50000 &&
  estimate([28.3, 40.7, 30.1, 41.4], PRESETS.streets, VT).refused === 'tiles' && /smaller area/i.test(estimate([28.3, 40.7, 30.1, 41.4], PRESETS.streets, VT).advice));
const mid = [28.8, 40.9, 29.3, 41.15];
check('estimate: VersaTiles accepts what OpenFreeMap refuses', estimate(mid, PRESETS.streets, VT).refused === null &&
  estimate(mid, PRESETS.streets, OFM).refused !== null, estimate(mid, PRESETS.streets, VT).vectorTiles);

// ---------------------------------------------------------------- sources and the polite fetcher
check('pickSource: the dormant one only by name', pickSource('?source=openfreemap').id === 'openfreemap' &&
  pickSource('').id === 'versatiles' && pickSource('?source=nope').id === 'versatiles');
check('sources: VersaTiles live, OpenFreeMap dormant', SOURCES.versatiles.enabled === true && SOURCES.openfreemap.enabled === false &&
  SOURCES.versatiles.schema === 'shortbread' && SOURCES.openfreemap.schema === 'openmaptiles' &&
  SOURCES.versatiles.limits.maxVectorTiles === 10000 && SOURCES.openfreemap.limits.maxVectorTiles === 3000);

function fakeCaches() {
  const m = new Map();
  return { m, open: async () => ({ match: async (k) => (m.has(k) ? new Response(m.get(k)) : undefined), put: async (k, r) => { m.set(k, new Uint8Array(await r.arrayBuffer())); } }) };
}
function fakeNet(plan = {}) {
  const net = { calls: [], inflight: 0, max: 0 };
  net.fetch = async (url, opt) => {
    net.calls.push(url);
    net.inflight++; net.max = Math.max(net.max, net.inflight);
    await new Promise((r) => setTimeout(r, 2));
    net.inflight--;
    if (opt?.signal?.aborted) throw new DOMException('aborted', 'AbortError');
    const p = plan[url]; if (p) { const a = p.shift(); if (a === 'net') throw new TypeError('Failed to fetch'); if (a) return a(); }
    if (url.includes('/404/')) return new Response('', { status: 404 });
    return new Response(new Uint8Array([1, 2, 3]), { status: 200 });
  };
  return net;
}
const src = { ...SOURCES.versatiles, tiles: 'https://t.example/{z}/{x}/{y}' };
{
  const net = fakeNet(), waits = [];
  const f = new TileFetcher(src, { fetch: net.fetch, caches: fakeCaches(), sleep: async (ms) => { waits.push(ms); } });
  await Promise.all(Array.from({ length: 20 }, (_, i) => f.get(14, i, 1)));
  check('fetcher: never more than 4 in flight', net.max <= 4 && net.max >= 2 && net.calls.length === 20, net.max);
  const again = await f.get(14, 3, 1);
  check('fetcher: the second get comes from the cache', net.calls.length === 20 && f.fromCache === 1 && again.length === 3);
  check('fetcher: a 404 is empty paper', (await f.get(14, 404, 1)) === null || (await new TileFetcher({ ...src, tiles: 'https://t.example/404/{z}/{x}/{y}' }, { fetch: net.fetch, caches: fakeCaches(), sleep: async () => {} }).get(1, 1, 1)) === null);
}
{
  const url = 'https://t.example/14/7/7';
  const net = fakeNet({ [url]: [() => new Response('', { status: 429, headers: { 'Retry-After': '2' } })] }), waits = [];
  const f = new TileFetcher(src, { fetch: net.fetch, caches: fakeCaches(), sleep: async (ms) => { waits.push(ms); } });
  const b = await f.get(14, 7, 7);
  check('fetcher: 429 waits Retry-After, then retries', waits[0] >= 2000 && b.length === 3 && net.calls.filter((u) => u === url).length === 2, waits);
}
{
  const url = 'https://t.example/14/8/8';
  const net = fakeNet({ [url]: ['net', 'net', 'net', 'net'] }), waits = [];
  const f = new TileFetcher(src, { fetch: net.fetch, caches: fakeCaches(), sleep: async (ms) => { waits.push(ms); } });
  let err = '';
  try { await f.get(14, 8, 8); } catch (e) { err = String(e.message || e); }
  check('fetcher: a network error retries 3 times, then names the tile', net.calls.length === 4 && waits.length === 3 && /14\/8\/8/.test(err), err);
}
{
  const net = fakeNet();
  const f = new TileFetcher({ ...src, limits: { ...src.limits, maxVectorTiles: 3 } }, { fetch: net.fetch, caches: fakeCaches(), sleep: async () => {} });
  await f.get(14, 1, 1); await f.get(14, 2, 1); await f.get(14, 3, 1);
  let err = '';
  try { await f.get(14, 4, 1); } catch (e) { err = String(e.message || e); }
  check('fetcher: over the limit rejects with limit', err === 'limit' && (await f.get(14, 1, 1)).length === 3, err);
}
{
  const net = fakeNet(), ac = new AbortController();
  const f = new TileFetcher(src, { fetch: net.fetch, caches: fakeCaches(), sleep: async () => {}, signal: ac.signal });
  const ps = Array.from({ length: 12 }, (_, i) => f.get(14, i, 9).then(() => 'ok', (e) => e.name || String(e)));
  ac.abort();
  const res = await Promise.all(ps);
  check('fetcher: abort rejects pending gets and starts nothing more', res.filter((r) => r === 'AbortError').length >= 8 && net.calls.length <= 4, `${res} ${net.calls.length}`);
}

// ---------------------------------------------------------------- e-ink roles and the two schemas
const KNOWN = {
  shortbread: ['ocean', 'water_polygons', 'water_lines', 'land', 'sites', 'buildings', 'streets', 'street_labels', 'place_labels', 'pois',
    'public_transport', 'water_polygons_labels', 'water_lines_labels', 'bridges', 'aerialways', 'addresses'],
  openmaptiles: ['water', 'waterway', 'landcover', 'landuse', 'park', 'building', 'transportation', 'transportation_name', 'place', 'poi',
    'mountain_peak', 'water_name', 'housenumber', 'aeroway'],
};
const colours = (o) => JSON.stringify(o).match(/#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)|hsla?\([^)]*\)/g) || [];
for (const sc of [shortbread, openmaptiles]) {
  const ls = sc.layers({ lang: 'local' });
  const roles = new Set(ls.map((l) => l.metadata?.['xt:role']).filter(Boolean));
  const want = ROLES.filter((r) => !sc.missing.includes(r));
  const lacking = want.filter((r) => !roles.has(r));
  check(`${sc.id}: every role drawn`, lacking.length === 0, lacking.join(', '));
  const unknown = ls.filter((l) => l['source-layer'] && !KNOWN[sc.id].includes(l['source-layer'])).map((l) => l['source-layer']);
  check(`${sc.id}: only known source layers`, unknown.length === 0, unknown.join(', '));
  check(`${sc.id}: every data layer on source xt`, ls.every((l) => !l['source-layer'] || l.source === 'xt'));
  const grey = ls.flatMap((l) => colours({ p: l.paint, y: l.layout })).filter((c) => !/^#(000|fff|000000|ffffff)$/i.test(c));
  check(`${sc.id}: black and white only`, grey.length === 0, grey.join(' '));
  const lbl = (lang) => sc.layers({ lang }).filter((l) => /-label$/.test(l.metadata?.['xt:role'] || '')).map((l) => JSON.stringify(l.layout['text-field']));
  check(`${sc.id}: English labels fall back to the local name`, lbl('en').every((t) => t === JSON.stringify(['coalesce', ['get', 'name_en'], ['get', 'name']])) && lbl('en').length > 2);
  check(`${sc.id}: local labels use name`, lbl('local').every((t) => t === JSON.stringify(['get', 'name'])));
  check(`${sc.id}: ids unique`, new Set(ls.map((l) => l.id)).size === ls.length);
}
check('shortbread misses only peaks', eq(shortbread.missing, ['peak']) && eq(openmaptiles.missing, []));
const pt = (x, y) => ({ type: 'Point', coordinates: [x, y] });
const kad = shortbread.nameEntry('place_labels', { kind: 'suburb', name: 'Kadıköy', name_en: 'Kadikoy' }, pt(29.0275, 40.9903), 'local');
check('shortbread: a suburb label is kind 4', kad && kad.kind === 4 && kad.name === 'Kadıköy' && kad.lon === 29.0275, JSON.stringify(kad));
check('shortbread: English name when asked', shortbread.nameEntry('place_labels', { kind: 'suburb', name: 'Kadıköy', name_en: 'Kadikoy' }, pt(29, 41), 'en').name === 'Kadikoy');
const line = { type: 'MultiLineString', coordinates: [[[29.0, 40.98], [29.001, 40.98]], [[29.02, 40.98], [29.025, 40.981], [29.03, 40.982]]] };
const moda = shortbread.nameEntry('street_labels', { kind: 'residential', name: 'Moda Caddesi' }, line, 'local');
check('shortbread: a street is kind 6 at the middle of its longest part', moda && moda.kind === 6 && moda.lon === 29.025 && moda.lat === 40.981, JSON.stringify(moda));
check('shortbread: a station is kind 7', shortbread.nameEntry('public_transport', { kind: 'station', name: 'Haydarpaşa' }, pt(29.019, 40.997), 'local')?.kind === 7);
check('openmaptiles: a peak is kind 8', openmaptiles.nameEntry('mountain_peak', { name: 'Uludağ', ele: 2543 }, pt(29.22, 40.07), 'local')?.kind === 8);
check('openmaptiles: a town is kind 2', openmaptiles.nameEntry('place', { class: 'town', name: 'Bursa' }, pt(29, 40.2), 'local')?.kind === 2);
check('no name -> null', shortbread.nameEntry('place_labels', { kind: 'suburb' }, pt(29, 41), 'local') === null &&
  openmaptiles.nameEntry('poi', { class: 'cafe' }, pt(29, 41), 'local') === null);
const img = symbolImage('poi-station');
check('symbol images are 1-bit RGBA', img.width > 0 && img.data.length === img.width * img.height * 4 &&
  [...img.data].every((v, i) => (i % 4 === 3 ? v === 0 || v === 255 : v === 0 || v === 255)));
const pat = patternImage('water');
check('pattern images are black and white', pat.width > 0 && [...pat.data].every((v) => v === 0 || v === 255));

// ---------------------------------------------------------------- metatiles, threshold, cut
const mts = metatiles({ x0: 10, y0: 20, nx: 9, ny: 5 }, 4);
check('metatiles: 3 x 2, the last ones narrower', mts.length === 6 && mts[0].x === 10 && mts[0].cols === 4 &&
  mts.find((m) => m.x === 18).cols === 1 && mts.find((m) => m.y === 24).rows === 1, JSON.stringify(mts));
{
  const pat = Array.from({ length: 64 }, (_, i) => ((i * 7) % 3 === 0 ? 1 : 0));
  const rgbaImg = new Uint8ClampedArray(16 * 16 * 4);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const v = pat[(y >> 1) * 8 + (x >> 1)] ? 0 : 255, i = 4 * (y * 16 + x);
    rgbaImg[i] = rgbaImg[i + 1] = rgbaImg[i + 2] = v; rgbaImg[i + 3] = 255;
  }
  const bits = toBits(rgbaImg, 16, 16, 2, 150);
  check('toBits: a 2x picture back to its 8x8 pattern', bits.length === 64 && eq([...bits], pat));
  const grey = new Uint8ClampedArray(4 * 4 * 4).fill(140);
  check('toBits: grey below the threshold is black', toBits(grey, 4, 4, 2, 150).every((b) => b === 1) &&
    toBits(new Uint8ClampedArray(64).fill(200), 4, 4, 2, 150).every((b) => b === 0));
}
{
  const w = 256 * 2 + 2 * 256;                        // two tiles a side plus a margin of 256
  const big = new Uint8Array(w * w);
  big[(256 + 256 + 3) * w + (256 + 256 + 5)] = 1;    // tile (1, 1), pixel (5, 3)
  const t = cut(big, w, 256, 1, 1);
  check('cut: the right window', t.length === 65536 && t[3 * 256 + 5] === 1 && t.reduce((a, b) => a + b, 0) === 1 && cut(big, w, 256, 0, 0).every((b) => b === 0));
}

{
  // a browser where Cache Storage fails (seen in the app's browser pane): fetch on without a cache
  const net = fakeNet();
  const broken = { open: async () => { throw new Error('Unexpected internal error.'); } };
  const f = new TileFetcher(src, { fetch: net.fetch, caches: broken, sleep: async () => {} });
  const b1 = await f.get(14, 1, 2);
  const b2 = await f.get(14, 1, 2);
  check('fetcher: no Cache Storage, still fetches', b1.length === 3 && b2.length === 3 && f.cacheOk === false && net.calls.length === 2);
}

// ---------------------------------------------------------------- review fixes
{
  // I3: a key run across several blocks is found in full
  const nm = [];
  for (let i = 0; i < 400; i++) nm.push({ name: 'Moda', kind: 6, lon: 29 + i / 1e4, lat: 41 });
  for (let i = 0; i < 300; i++) nm.push({ name: `Aaa ${i}`, kind: 6, lon: 29, lat: 41 }, { name: `Zzz ${i}`, kind: 6, lon: 29, lat: 41 });
  const r3 = readPack(writePack({ meta, levels: [{ z: 15, x0: 0, y0: 0, nx: 1, ny: 1, tiles: [null] }], names: nm }));
  check('search: a name in 400 entries across blocks, all found', r3.search('moda', 1000).length === 400, r3.search('moda', 1000).length);
}
{
  // I4: a body cut off mid-download is fetched again
  let n4 = 0;
  const f4 = new TileFetcher(src, { caches: null, sleep: async () => {}, fetch: async () => {
    n4++;
    if (n4 === 1) return { status: 200, ok: true, headers: new Headers(), arrayBuffer: async () => { throw new TypeError('network error'); } };
    return new Response(new Uint8Array([7, 7]), { status: 200 });
  } });
  const b4 = await f4.get(14, 2, 2).catch((e) => e);
  check('fetcher: a broken body is retried', b4 instanceof Uint8Array && b4.length === 2 && n4 === 2, String(b4));
  const f5 = new TileFetcher(src, { caches: null, sleep: async () => {}, fetch: async () => new Response('', { status: 429, headers: { 'Retry-After': '600' } }) });
  const e5 = await f5.get(14, 3, 3).catch((e) => e);
  check('fetcher: a long Retry-After gives up with the wait', e5 instanceof Error && /10 min/.test(e5.message), String(e5));
}

// ---------------------------------------------------------------- Task 14: drawing a route
check('route: 1 degree of meridian', Math.abs(lengthM([[29, 40], [29, 41]]) - 111195) <= 200, lengthM([[29, 40], [29, 41]]));
{
  const bb = bboxWithMargin([[29.0, 41.0], [29.01, 41.005]], 500);
  const dLat = 500 / 111195, dLon = 500 / (111195 * Math.cos(41.0025 * Math.PI / 180));
  check('route: bbox with a 500 m margin', Math.abs(bb[0] - (29.0 - dLon)) < 1e-4 && Math.abs(bb[1] - (41.0 - dLat)) < 1e-4 &&
    Math.abs(bb[2] - (29.01 + dLon)) < 1e-4 && Math.abs(bb[3] - (41.005 + dLat)) < 1e-4, JSON.stringify(bb));
}
{
  const g = toGpx({ name: 'Walk & <run>', points: [[29.0251, 40.9871], [29.0262, 40.9855]], labels: [{ name: 'A & B Sokağı', lon: 29.0256, lat: 40.9863 }] });
  const back = parseGpx(g);
  check('route: toGpx round trip, names escaped', back.name === 'Walk & <run>' && back.points.length === 2 &&
    Math.abs(back.points[1][0] - 29.0262) < 1e-7 && /<type>street<\/type>/.test(g) && g.includes('A &amp; B Sokağı') && !/<run>/.test(g));
}
{
  // a route along a label line (north-south) and a crossing one (east-west)
  const along = { type: 'Feature', properties: { name: 'Moda Caddesi' }, geometry: { type: 'LineString', coordinates: [[29.0250, 40.9850], [29.0250, 40.9880]] } };
  const cross = { type: 'Feature', properties: { name: 'Cross Sokak' }, geometry: { type: 'LineString', coordinates: [[29.0240, 40.9865], [29.0260, 40.9865]] } };
  const r = [[29.02501, 40.9852], [29.02501, 40.9878]];
  const lab = streetLabels(r, [along, cross]);
  check('route: street labels name the street it follows, not one it crosses', lab.length === 1 && lab[0].name === 'Moda Caddesi' &&
    Math.abs(lab[0].lat - 40.9865) < 0.001, JSON.stringify(lab));
}

console.log('\n' + (bad ? `${bad} of ${n} FAILED` : `all passed (${n})`));
process.exit(bad ? 1 : 0);
