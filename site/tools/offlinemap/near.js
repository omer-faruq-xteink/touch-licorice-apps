// The pack's nearest-name section (header bytes 36-43; apps/offlinemap/src/near.lua reads it): what a
// long press on the map names. The named lines (streets, paths, rivers), named points (places,
// stations, peaks) and named areas (lakes, parks) of the pack, cut into buckets of one tile at zoom
// zb, so a long press reads one bucket, or a few. Each record says from which output zoom the map
// draws it, so the reader names only what it shows.
//   head (16 B): zb u8, 3 B unused, x0 u32, y0 u32, nx u16, ny u16
//   index: nx * ny x (offset u32 within the section, length u32), row-major
//   buckets: records of kind u8, from u8 (zoom), shape u8 (0 point, 1 line, 2 area), name length u8,
//            name (UTF-8), n u16, n x (dx i16, dy i16)
// Points are pixels at zoom zb + 5 (UNIT a tile) from the bucket's top left corner. A line is in
// every bucket its segments' boxes touch, as runs of the segments there; an area's outer ring (a
// piece of it from one vector tile) is in every bucket its box touches.
import { tileRange, lonLatToTile } from './tiles.js';
import { cutUtf8 } from './pack.js';

export const UNIT = 8192;
const I16 = 32767;

// the output zoom from which the style draws each kind of point and line (eink.js, schema/*.js): the
// data's own first level can be later. Areas (lakes, parks) are drawn from the start.
export const STYLE_FROM = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 12, 7: 13, 8: 13, 12: 13, 13: 0 };

// is [x, y] inside the ring (even-odd)?
export function inRing([x, y], ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

// the drawn areas' pieces [{id, kind, ring}] and the labels [{id, name, kind, lon, lat}] -> the named
// ones [{name, kind, id, area: true, lines: [ring]}]: the label with the same id (the data's link
// between a lake and its name), else a label of the same kind inside the piece
export function nameAreas(polys, labels) {
  const byId = new Map();
  for (const l of labels) if (l.id != null && !byId.has(l.id)) byId.set(l.id, l);
  const out = [];
  for (const p of polys) {
    let l = p.id != null ? byId.get(p.id) : null;
    if (l && l.kind !== p.kind) l = null;
    if (!l) l = labels.find((q) => q.kind === p.kind && inRing([q.lon, q.lat], p.ring)) || null;
    if (l) out.push({ name: l.name, kind: p.kind, id: p.id, area: true, lines: [p.ring] });
  }
  return out;
}

// features [{name, kind, from, area?, lines: [[[lon, lat], ...], ...]}] (a point is a line of one;
// an area has its ring as its one line) -> the section, or null
export function nearSection(features, bbox, zb) {
  const r = tileRange(bbox, zb);
  const buckets = new Map();                       // index -> { recs: [{kind, from, shape, name, pts}], last }
  const bucket = (bx, by) => {
    const i = (by - r.y0) * r.nx + (bx - r.x0);
    let b = buckets.get(i);
    if (!b) { b = { recs: [], last: null }; buckets.set(i, b); }
    return b;
  };
  const inGrid = (bx, by) => bx >= r.x0 && by >= r.y0 && bx < r.x0 + r.nx && by < r.y0 + r.ny;
  const px = ([lon, lat]) => { const t = lonLatToTile(lon, lat, zb); return [t.x * UNIT, t.y * UNIT]; };
  const rel = (p, bx, by) => [Math.round(p[0] - bx * UNIT), Math.round(p[1] - by * UNIT)];
  const fits = (q) => Math.abs(q[0]) <= I16 && Math.abs(q[1]) <= I16;
  // the buckets of the grid a box of pixels touches
  const each = (pts, fn) => {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const [x, y] of pts) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    for (let by = Math.max(r.y0, Math.floor(y0 / UNIT)); by <= Math.min(r.y0 + r.ny - 1, Math.floor(y1 / UNIT)); by++) {
      for (let bx = Math.max(r.x0, Math.floor(x0 / UNIT)); bx <= Math.min(r.x0 + r.nx - 1, Math.floor(x1 / UNIT)); bx++) fn(bx, by);
    }
  };
  let id = 0;
  for (const f of features) {
    const name = cutUtf8(f.name);
    if (!name.length) continue;
    const from = Math.max(0, Math.min(255, f.from ?? 0));
    for (const line of f.lines) {
      const pts = line.map(px);
      const run = ++id;
      if (f.area) {
        if (pts.length < 4 || pts.length > 65535) continue;
        each(pts, (bx, by) => {
          const q = pts.map((p) => rel(p, bx, by));
          if (q.every(fits)) bucket(bx, by).recs.push({ kind: f.kind, from, shape: 2, name, pts: q });
        });
      } else if (pts.length === 1) {
        const bx = Math.floor(pts[0][0] / UNIT), by = Math.floor(pts[0][1] / UNIT);
        if (inGrid(bx, by)) bucket(bx, by).recs.push({ kind: f.kind, from, shape: 0, name, pts: [rel(pts[0], bx, by)] });
      } else {
        for (let i = 1; i < pts.length; i++) {
          const a = pts[i - 1], b = pts[i];
          each([a, b], (bx, by) => {
            const qa = rel(a, bx, by), qb = rel(b, bx, by);
            if (!fits(qa) || !fits(qb)) return;
            const bk = bucket(bx, by);
            if (bk.last && bk.last.run === run && bk.last.end === i - 1) { bk.last.rec.pts.push(qb); bk.last.end = i; }
            else {
              const rec = { kind: f.kind, from, shape: 1, name, pts: [qa, qb] };
              bk.recs.push(rec);
              bk.last = { run, end: i, rec };
            }
          });
        }
      }
    }
  }
  if (!buckets.size) return null;
  const parts = new Array(r.nx * r.ny).fill(null);
  for (const [i, b] of buckets) {
    const chunks = [], seen = new Set();
    for (const rec of b.recs) {
      const key = `${rec.kind}|${rec.from}|${rec.shape}|${rec.name.join(',')}|${rec.pts.join(';')}`;
      if (seen.has(key)) continue;                   // the same piece from two vector tiles
      seen.add(key);
      for (let s = 0; s < rec.pts.length; s += 65535) {
        const pts = rec.pts.slice(s, s + 65535);
        const out = new Uint8Array(4 + rec.name.length + 2 + 4 * pts.length);
        const v = new DataView(out.buffer);
        out[0] = rec.kind; out[1] = rec.from; out[2] = rec.shape; out[3] = rec.name.length; out.set(rec.name, 4);
        let p = 4 + rec.name.length;
        v.setUint16(p, pts.length, true); p += 2;
        for (const [x, y] of pts) { v.setInt16(p, x, true); v.setInt16(p + 2, y, true); p += 4; }
        chunks.push(out);
      }
    }
    const all = new Uint8Array(chunks.reduce((t, c) => t + c.length, 0));
    let p = 0;
    for (const c of chunks) { all.set(c, p); p += c.length; }
    parts[i] = all;
  }
  const head = 16 + 8 * r.nx * r.ny;
  const out = new Uint8Array(head + parts.reduce((t, b) => t + (b ? b.length : 0), 0));
  const v = new DataView(out.buffer);
  out[0] = zb;
  v.setUint32(4, r.x0, true); v.setUint32(8, r.y0, true);
  v.setUint16(12, r.nx, true); v.setUint16(14, r.ny, true);
  let p = head;
  parts.forEach((b, i) => {
    if (!b || !b.length) return;
    v.setUint32(16 + 8 * i, p, true);
    v.setUint32(20 + 8 * i, b.length, true);
    out.set(b, p); p += b.length;
  });
  return out;
}
