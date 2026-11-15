// The Offline Map pack, format v1 (docs/superpowers/plans/2026-11-15-offline-map.md, "Pack format
// v1"; apps/offlinemap/src/pack.lua reads it). Little endian:
//   header (64 B) | meta JSON | zoom table (20 B a level) | an index per level (8 B a tile) |
//   the tiles, row-major per level | the name index (directory, then blocks of <= 4096 B)
import { fold } from './fold.js';

const enc = new TextEncoder();
export const BLOCK = 4096;
export const MAX_DIR = 65536;

// a UTF-8 string cut to at most n bytes without breaking a character
export function cutUtf8(s, n = 255) {
  let b = enc.encode(s);
  if (b.length <= n) return b;
  let end = n;
  while (end > 0 && (b[end] & 0xc0) === 0x80) end--;
  return b.subarray(0, end);
}

// names: [{name, kind, lon, lat}] -> the name section (directory + blocks), or null when empty
export function nameSection(names) {
  if (!names.length) return null;
  const items = names.map((e) => {
    const name = cutUtf8(e.name);
    const key = cutUtf8(fold(new TextDecoder().decode(name)));
    return { key, name, kind: e.kind, lon7: Math.round(e.lon * 1e7), lat7: Math.round(e.lat * 1e7) };
  }).filter((e) => e.key.length > 0);
  const cmp = (a, b) => {
    const n = Math.min(a.length, b.length);
    for (let i = 0; i < n; i++) if (a[i] !== b[i]) return a[i] - b[i];
    return a.length - b.length;
  };
  items.sort((a, b) => cmp(a.key, b.key) || cmp(a.name, b.name));
  const entry = (e) => {
    const out = new Uint8Array(1 + e.key.length + 1 + e.name.length + 1 + 8);
    const v = new DataView(out.buffer);
    let p = 0;
    out[p++] = e.key.length; out.set(e.key, p); p += e.key.length;
    out[p++] = e.name.length; out.set(e.name, p); p += e.name.length;
    out[p++] = e.kind;
    v.setInt32(p, e.lon7, true); v.setInt32(p + 4, e.lat7, true);
    return out;
  };
  const blocks = [];
  let cur = [], size = 0;
  for (const e of items) {
    const b = entry(e);
    if (size + b.length > BLOCK && cur.length) { blocks.push(cur); cur = []; size = 0; }
    cur.push({ e, b }); size += b.length;
  }
  if (cur.length) blocks.push(cur);
  let dirLen = 4;
  for (const bl of blocks) dirLen += 4 + 2 + 2 + 1 + bl[0].e.key.length;
  if (dirLen > MAX_DIR) throw new Error('too many names for one pack');
  const total = dirLen + blocks.reduce((s, bl) => s + bl.reduce((t, x) => t + x.b.length, 0), 0);
  const out = new Uint8Array(total);
  const v = new DataView(out.buffer);
  v.setUint32(0, blocks.length, true);
  let d = 4, p = dirLen;
  for (const bl of blocks) {
    const len = bl.reduce((t, x) => t + x.b.length, 0);
    v.setUint32(d, p, true);                        // offset within the names section
    v.setUint16(d + 4, len, true);
    v.setUint16(d + 6, bl.length, true);
    out[d + 8] = bl[0].e.key.length;
    out.set(bl[0].e.key, d + 9);
    d += 9 + bl[0].e.key.length;
    for (const x of bl) { out.set(x.b, p); p += x.b.length; }
  }
  return out;
}

// {meta, levels: [{z, x0, y0, nx, ny, tiles: (Uint8Array|null)[] row-major}], names} -> the file
export function writePack({ meta, levels, names = [] }) {
  const lv = [...levels].sort((a, b) => a.z - b.z);
  const metaB = enc.encode(JSON.stringify(meta));
  const names_ = nameSection(names);
  const zoomOff = 64 + metaB.length;
  let idxOff = zoomOff + 20 * lv.length;
  const idxOffs = lv.map((l) => { const o = idxOff; idxOff += 8 * l.nx * l.ny; return o; });
  let dataLen = 0;
  for (const l of lv) for (const t of l.tiles) if (t) dataLen += t.length;
  const tilesOff = idxOff;
  const namesOff = tilesOff + dataLen;
  const total = namesOff + (names_ ? names_.length : 0);
  if (total >= 2 ** 31) throw new Error('pack too large');
  const out = new Uint8Array(total);
  const v = new DataView(out.buffer);
  out.set(enc.encode('XTMAP1\0\0'), 0);
  v.setUint16(8, 1, true);
  out[10] = lv.length;
  out[11] = 2;
  v.setUint16(12, 256, true);
  v.setUint32(16, 64, true);
  v.setUint32(20, metaB.length, true);
  v.setUint32(24, zoomOff, true);
  v.setUint32(28, names_ ? namesOff : 0, true);
  v.setUint32(32, names_ ? names_.length : 0, true);
  out.set(metaB, 64);
  let p = tilesOff;
  lv.forEach((l, i) => {
    if (l.tiles.length !== l.nx * l.ny) throw new Error(`level ${l.z}: ${l.tiles.length} tiles for ${l.nx}x${l.ny}`);
    const zo = zoomOff + 20 * i;
    out[zo] = l.z;
    v.setUint32(zo + 4, l.x0, true);
    v.setUint32(zo + 8, l.y0, true);
    v.setUint16(zo + 12, l.nx, true);
    v.setUint16(zo + 14, l.ny, true);
    v.setUint32(zo + 16, idxOffs[i], true);
    l.tiles.forEach((t, k) => {
      const e = idxOffs[i] + 8 * k;
      if (t && t.length) {
        v.setUint32(e, p, true);
        v.setUint32(e + 4, t.length, true);
        out.set(t, p);
        p += t.length;
      }
    });
  });
  if (names_) out.set(names_, namesOff);
  return out;
}
