// A port of the Offline Map app's pack reader (apps/offlinemap/src/pack.lua), for the tests only:
// readPack(bytes) -> { header, meta, levels, nameBlocks, tile(z, x, y), search(prefix, limit) }.
import { fold } from '../tools/offlinemap/fold.js';

const dec = new TextDecoder();

export async function unzlib(bytes) {
  const ds = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate'));
  return new Uint8Array(await new Response(ds).arrayBuffer());
}

export function readPack(bytes) {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const header = {
    magic: dec.decode(bytes.subarray(0, 8)), version: v.getUint16(8, true), levels: bytes[10], format: bytes[11],
    tileSize: v.getUint16(12, true), metaOff: v.getUint32(16, true), metaLen: v.getUint32(20, true),
    zoomOff: v.getUint32(24, true), namesOff: v.getUint32(28, true), namesLen: v.getUint32(32, true),
    nearOff: v.getUint32(36, true), nearLen: v.getUint32(40, true),
  };
  if (header.magic !== 'XTMAP1\0\0' || header.version !== 1) throw new Error('not a map pack');
  const meta = JSON.parse(dec.decode(bytes.subarray(header.metaOff, header.metaOff + header.metaLen)));
  const levels = [];
  for (let i = 0; i < header.levels; i++) {
    const o = header.zoomOff + 20 * i;
    levels.push({ z: bytes[o], x0: v.getUint32(o + 4, true), y0: v.getUint32(o + 8, true),
      nx: v.getUint16(o + 12, true), ny: v.getUint16(o + 14, true), index: v.getUint32(o + 16, true) });
  }
  function tile(z, x, y) {
    const l = levels.find((q) => q.z === z);
    if (!l || x < l.x0 || y < l.y0 || x >= l.x0 + l.nx || y >= l.y0 + l.ny) return null;
    const e = l.index + 8 * ((y - l.y0) * l.nx + (x - l.x0));
    const off = v.getUint32(e, true), len = v.getUint32(e + 4, true);
    return len ? bytes.subarray(off, off + len) : null;
  }
  // the name directory
  const dir = [];
  if (header.namesLen) {
    const base = header.namesOff;
    const nb = v.getUint32(base, true);
    let d = base + 4;
    for (let i = 0; i < nb; i++) {
      const klen = bytes[d + 8];
      dir.push({ off: base + v.getUint32(d, true), len: v.getUint16(d + 4, true), count: v.getUint16(d + 6, true),
        first: dec.decode(bytes.subarray(d + 9, d + 9 + klen)) });
      d += 9 + klen;
    }
  }
  const enc = new TextEncoder();
  const lt = (a, b) => {               // byte order, as the writer sorts
    const x = enc.encode(a), y = enc.encode(b);
    for (let i = 0; i < Math.min(x.length, y.length); i++) if (x[i] !== y[i]) return x[i] < y[i];
    return x.length < y.length;
  };
  function entries(bl) {
    const out = [];
    let p = bl.off;
    for (let i = 0; i < bl.count; i++) {
      const kl = bytes[p]; const key = dec.decode(bytes.subarray(p + 1, p + 1 + kl)); p += 1 + kl;
      const nl = bytes[p]; const name = dec.decode(bytes.subarray(p + 1, p + 1 + nl)); p += 1 + nl;
      const kind = bytes[p]; p += 1;
      out.push({ key, name, kind, lon7: v.getInt32(p, true), lat7: v.getInt32(p + 4, true) });
      p += 8;
    }
    return out;
  }
  function search(prefix, limit = 20) {
    const q = fold(prefix);
    if (!q || !dir.length) return [];
    // the last block whose first key is <= q, then on while keys can still start with q
    let lo = 0, hi = dir.length - 1, at = 0;
    while (lo <= hi) { const m = (lo + hi) >> 1; if (lt(dir[m].first, q)) { at = m; lo = m + 1; } else hi = m - 1; }
    const out = [];
    for (let b = at; b < dir.length && out.length < limit; b++) {
      if (b > at && !dir[b].first.startsWith(q)) break;
      for (const e of entries(dir[b])) if (e.key.startsWith(q) && out.length < limit) out.push(e);
    }
    return out;
  }
  // the nearest-name section (near.js)
  function nearHead() {
    if (!header.nearLen) return null;
    const o = header.nearOff;
    return { zb: bytes[o], x0: v.getUint32(o + 4, true), y0: v.getUint32(o + 8, true), nx: v.getUint16(o + 12, true), ny: v.getUint16(o + 14, true) };
  }
  function nearBucket(bx, by) {
    const h = nearHead();
    if (!h || bx < h.x0 || by < h.y0 || bx >= h.x0 + h.nx || by >= h.y0 + h.ny) return null;
    const e = header.nearOff + 16 + 8 * ((by - h.y0) * h.nx + (bx - h.x0));
    let p = header.nearOff + v.getUint32(e, true);
    const end = p + v.getUint32(e + 4, true), out = [];
    while (p < end) {
      const kind = bytes[p], from = bytes[p + 1], shape = bytes[p + 2], nl = bytes[p + 3];
      const name = dec.decode(bytes.subarray(p + 4, p + 4 + nl)); p += 4 + nl;
      const n = v.getUint16(p, true); p += 2;
      const pts = [];
      for (let i = 0; i < n; i++) { pts.push([v.getInt16(p, true), v.getInt16(p + 2, true)]); p += 4; }
      out.push({ kind, from, shape, name, pts });
    }
    return out;
  }
  return { header, meta, levels, nameBlocks: dir.length, tile, search, nearHead, nearBucket };
}
