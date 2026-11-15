// Rendering a pack: MapLibre draws the e-ink style offscreen, a metatile of 4 x 4 output tiles (plus
// a margin of one tile, so labels at the edges are whole) at a time, at pixelRatio 2; the picture is
// halved with a box filter, thresholded to 1 bit and cut into 256 px tiles (zlib-compressed 1-bit
// BMPs). Names for the search index come from the vector features of one level.
import { bmp1, zlib, isBlank } from './bmpz.js';
import { writePack } from './pack.js';
import { tileRange, tileToLonLat, vectorZoom } from './tiles.js';
import { TileFetcher, registerProtocol } from './fetcher.js';
import { GLYPHS, SYMBOL_ROLES, PATTERN_NAMES, symbolImage, patternImage, doubled } from './eink.js';
import { fold } from './fold.js';
import { streetLabels, toGpx } from './route.js';

export const N = 4;                 // tiles a side per metatile
export const MARGIN = 256;          // output pixels around it
export const THRESHOLD = 150;       // luma below this is black (the spike's value; tune on the device)
const T = 256;

// a level's tile range -> metatiles of at most n x n tiles
export function metatiles(range, n = N) {
  const out = [];
  for (let y = range.y0; y < range.y0 + range.ny; y += n) {
    for (let x = range.x0; x < range.x0 + range.nx; x += n) {
      out.push({ x, y, cols: Math.min(n, range.x0 + range.nx - x), rows: Math.min(n, range.y0 + range.ny - y) });
    }
  }
  return out;
}

// device-pixel RGBA (w x h) -> output bits (w/scale x h/scale), 1 = black
export function toBits(rgba, w, h, scale = 2, threshold = THRESHOLD) {
  const ow = Math.floor(w / scale), oh = Math.floor(h / scale);
  const out = new Uint8Array(ow * oh);
  const k = scale * scale;
  for (let y = 0; y < oh; y++) {
    for (let x = 0; x < ow; x++) {
      let sum = 0;
      for (let dy = 0; dy < scale; dy++) {
        let i = 4 * ((y * scale + dy) * w + x * scale);
        for (let dx = 0; dx < scale; dx++, i += 4) sum += 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
      }
      out[y * ow + x] = sum / k < threshold ? 1 : 0;
    }
  }
  return out;
}

// one tile out of a metatile's bits (width w, margin m)
export function cut(bits, w, m, col, row) {
  const t = new Uint8Array(T * T);
  const x0 = m + col * T, y0 = m + row * T;
  for (let y = 0; y < T; y++) t.set(bits.subarray((y0 + y) * w + x0, (y0 + y) * w + x0 + T), y * T);
  return t;
}

const abortError = () => new DOMException('The run was cancelled.', 'AbortError');
const metres = (a, b) => {
  const r = Math.PI / 180, x = (b[0] - a[0]) * r * Math.cos(((a[1] + b[1]) / 2) * r), y = (b[1] - a[1]) * r;
  return Math.hypot(x, y) * 6371000;
};

// the level names are read at: the lowest level drawn from the deepest vector zoom used
export function nameLevel(levels) {
  const deepest = Math.max(...levels.map(vectorZoom));
  return Math.min(...levels.filter((z) => vectorZoom(z) === deepest));
}

// -> true when the view settled, false when it timed out
function waitIdle(map, signal) {
  return new Promise((resolve, reject) => {
    const done = () => { clearTimeout(timer); resolve(true); };
    const timer = setTimeout(() => resolve(false), 60000);   // never hang
    map.once('idle', done);
    signal?.addEventListener('abort', () => { clearTimeout(timer); reject(abortError()); }, { once: true });
    map.triggerRepaint();
  });
}

// -> { bytes, stats }
export async function renderPack({ bbox, levels, name, lang = 'local', source, schema, maplibregl, fetcher, onProgress, signal }) {
  fetcher = fetcher || new TileFetcher(source, { signal });
  await fetcher.resolve();
  registerProtocol(maplibregl, fetcher);
  const side = N * T + 2 * MARGIN;
  const box = document.createElement('div');
  box.style.cssText = `position:absolute;left:-20000px;top:0;width:${side}px;height:${side}px;`;
  document.body.append(box);
  let failure = null;
  const map = new maplibregl.Map({
    container: box, pixelRatio: 2, interactive: false, fadeDuration: 0, preserveDrawingBuffer: true,
    attributionControl: false, center: [0, 0], zoom: 0, maxZoom: 22,
    style: { version: 8, glyphs: GLYPHS, sources: { xt: { type: 'vector', tiles: ['xtmap://{z}/{x}/{y}'], maxzoom: source.maxzoom } },
      layers: schema.layers({ lang }) },
  });
  // any failed map tile fails the run (a pack with holes is worse than none; Make again resumes)
  map.on('error', (e) => {
    const m = String(e?.error?.message || e?.error || '');
    if (e?.sourceId === 'xt' || e?.tile || /^limit$|cancelled|map tile|map server|HTTP/.test(m)) failure = failure || m || 'A map tile failed to load.';
  });
  const scratch = document.createElement('canvas');
  scratch.width = scratch.height = side * 2;
  const c2 = scratch.getContext('2d', { willReadFrequently: true });
  try {
    await new Promise((resolve, reject) => {
      if (map.loaded()) { resolve(); return; }
      map.once('load', resolve);
      signal?.addEventListener('abort', () => reject(abortError()), { once: true });
    });
    for (const r of SYMBOL_ROLES) map.addImage(`xt-${r}`, doubled(symbolImage(r)), { pixelRatio: 2 });
    for (const p of PATTERN_NAMES) map.addImage(`xt-${p}`, doubled(patternImage(p)), { pixelRatio: 2 });
    // deepest level first: it holds most of the tiles, so the time left is right from the start
    const plans = [...levels].sort((a, b) => b - a).map((z) => ({ z, range: tileRange(bbox, z) }));
    const total = plans.reduce((s, p) => s + p.range.nx * p.range.ny, 0);
    const nl = nameLevel(levels);
    const names = new Map();
    const t0 = performance.now();
    let done = 0, empty = 0;
    const out = [];
    for (const { z, range } of plans) {
      const tiles = new Array(range.nx * range.ny).fill(null);
      for (const mt of metatiles(range)) {
        if (signal?.aborted) throw abortError();
        const c = tileToLonLat(mt.x + N / 2, mt.y + N / 2, z);
        map.jumpTo({ center: [c.lon, c.lat], zoom: z - 1 });
        const settled = await waitIdle(map, signal);
        if (!settled && (fetcher.busy() || !map.areTilesLoaded())) failure = failure || 'The map tiles did not all arrive in a minute. Check the connection and press Make again: what was fetched is kept.';
        if (failure) throw new Error(failure === 'limit' ? 'The area needs more map tiles than one pack may use.' : failure);
        c2.clearRect(0, 0, side * 2, side * 2);
        c2.drawImage(map.getCanvas(), 0, 0, side * 2, side * 2);
        const bits = toBits(c2.getImageData(0, 0, side * 2, side * 2).data, side * 2, side * 2, 2, THRESHOLD);
        for (let row = 0; row < mt.rows; row++) {
          for (let col = 0; col < mt.cols; col++) {
            const t = cut(bits, side, MARGIN, col, row);
            const i = (mt.y - range.y0 + row) * range.nx + (mt.x - range.x0 + col);
            if (isBlank(t)) { empty++; continue; }
            tiles[i] = await zlib(bmp1(t));
          }
        }
        if (z === nl) collectNames(map, schema, lang, bbox, names);
        done += mt.cols * mt.rows;
        const el = (performance.now() - t0) / 1000;
        onProgress?.({ done, total, vectorTiles: fetcher.count, fromCache: fetcher.fromCache, eta: done ? (el / done) * (total - done) : null });
      }
      out.push({ z, x0: range.x0, y0: range.y0, nx: range.nx, ny: range.ny, tiles });
    }
    const list = [...names.values()].flat();
    const meta = { name, bounds: bbox, levels, lang, made: new Date().toISOString().slice(0, 10),
      data_date: fetcher.dataDate || '', source: source.id, attribution: source.attribution, tool: 1 };
    const bytes = writePack({ meta, levels: out, names: list });
    return { bytes, stats: { tiles: total, empty, names: list.length, vectorTiles: fetcher.count, fromCache: fetcher.fromCache } };
  } finally {
    map.remove();
    box.remove();
  }
}

// the named features drawn at this view -> names (the same folded key and kind within 300 m kept once)
function collectNames(map, schema, lang, [w, s, e, n], names) {
  for (const sl of schema.nameLayers) {
    let feats = [];
    try { feats = map.querySourceFeatures('xt', { sourceLayer: sl }); } catch { continue; }
    for (const f of feats) {
      const ent = schema.nameEntry(sl, f.properties || {}, f.geometry, lang);
      if (!ent || ent.lon < w || ent.lon > e || ent.lat < s || ent.lat > n) continue;
      const key = `${fold(ent.name)}|${ent.kind}`;
      const have = names.get(key) || [];
      if (have.some((h) => metres([h.lon, h.lat], [ent.lon, ent.lat]) < 300)) continue;
      have.push(ent);
      names.set(key, have);
    }
  }
}

// the street label lines with a vertex near the route's box (50 m), for streetLabels
function collectStreets(map, schema, points, out, lang) {
  if (!schema.streetLabelLayer || points.length < 2) return;
  let w = Infinity, s = Infinity, e = -Infinity, n = -Infinity;
  for (const [x, y] of points) { w = Math.min(w, x); e = Math.max(e, x); s = Math.min(s, y); n = Math.max(n, y); }
  const m = 0.0006;
  let feats = [];
  try { feats = map.querySourceFeatures('xt', { sourceLayer: schema.streetLabelLayer }); } catch { return; }
  for (const f of feats) {
    const g = f.geometry;
    if (!g || !f.properties || !f.properties.name) continue;
    const parts = g.type === 'LineString' ? [g.coordinates] : g.type === 'MultiLineString' ? g.coordinates : [];
    if (parts.some((p) => p.some(([x, y]) => x > w - m && x < e + m && y > s - m && y < n + m))) {
      out.push({ type: 'Feature', properties: { name: (lang === 'en' && f.properties.name_en) || f.properties.name }, geometry: g });
    }
  }
}

// A route alone: the names of the streets it follows, from the vector tiles along it (map zoom 14,
// where the tiles hold every street label), without making a pack -> the route's GPX
export async function makeRouteGpx({ name, points, lang = 'local', source, schema, maplibregl, fetcher, onProgress, signal }) {
  fetcher = fetcher || new TileFetcher(source, { signal });
  await fetcher.resolve();
  registerProtocol(maplibregl, fetcher);
  const side = 1024;
  const box = document.createElement('div');
  box.style.cssText = `position:absolute;left:-20000px;top:0;width:${side}px;height:${side}px;`;
  document.body.append(box);
  let failure = null;
  // the street labels only: nothing else needs drawing
  const layers = schema.layers({ lang }).filter((l) => l['source-layer'] === schema.streetLabelLayer);
  const map = new maplibregl.Map({
    container: box, interactive: false, fadeDuration: 0, attributionControl: false, center: [0, 0], zoom: 0,
    style: { version: 8, glyphs: GLYPHS, sources: { xt: { type: 'vector', tiles: ['xtmap://{z}/{x}/{y}'], maxzoom: source.maxzoom } }, layers },
  });
  map.on('error', (e) => { if (e?.sourceId === 'xt' || e?.tile) failure = failure || String(e?.error?.message || 'A map tile failed to load.'); });
  try {
    await new Promise((resolve, reject) => {
      if (map.loaded()) { resolve(); return; }
      map.once('load', resolve);
      signal?.addEventListener('abort', () => reject(abortError()), { once: true });
    });
    // views of side px at map zoom 14 (output zoom 15) along the route
    const z = 15, half = side / 2;
    const px = points.map(([lon, lat]) => { const t = lonLatToPx(lon, lat, z); return [t.x, t.y]; });
    const centres = new Map();
    for (const [x, y] of px) {
      const cx = Math.floor(x / side) * side + half, cy = Math.floor(y / side) * side + half;
      centres.set(`${cx},${cy}`, [cx, cy]);
    }
    const streets = [];
    let done = 0;
    for (const [cx, cy] of centres.values()) {
      if (signal?.aborted) throw abortError();
      const c = tileToLonLat(cx / T, cy / T, z);
      map.jumpTo({ center: [c.lon, c.lat], zoom: z - 1 });
      const settled = await waitIdle(map, signal);
      if (!settled && (fetcher.busy() || !map.areTilesLoaded())) failure = failure || 'The map tiles did not all arrive in a minute. Check the connection and try again.';
      if (failure) throw new Error(failure);
      collectStreets(map, schema, points, streets, lang);
      onProgress?.({ done: ++done, total: centres.size });
    }
    const labels = streetLabels(points, streets);
    return { gpx: toGpx({ name, points, labels }), labels };
  } finally {
    map.remove();
    box.remove();
  }
}
const lonLatToPx = (lon, lat, z) => { const n = 2 ** z * T, r = lat * Math.PI / 180;
  return { x: (lon + 180) / 360 * n, y: (1 - Math.asinh(Math.tan(r)) / Math.PI) / 2 * n }; };
