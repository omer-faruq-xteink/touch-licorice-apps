// Fixture packs for the Offline Map app's tests (apps/offlinemap/test_offlinemap.py), written by the
// tool's own pack writer so both sides read the same bytes.
//   node site/test/offlinemap_cli.mjs fixtures OUT_DIR
// city.map     z15-16 around Kadıkoy, two empty z16 tiles, one z16 row of noise (> 70 KB), names
// inner.map    z15-17, smaller, inside city.map
// overview.map z8-13 over 28-30 E, 40.5-41.5 N
// Each tile's picture encodes where it is: its first (x + y) % 200 + 1 pixels are black.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { bmp1, zlib } from '../tools/offlinemap/bmpz.js';
import { writePack } from '../tools/offlinemap/pack.js';

const [, , what, out] = process.argv;
if (what !== 'fixtures' || !out) { console.error('usage: node offlinemap_cli.mjs fixtures OUT_DIR'); process.exit(2); }
mkdirSync(out, { recursive: true });

const tileXY = (lon, lat, z) => {
  const n = 2 ** z;
  return [Math.floor((lon + 180) / 360 * n), Math.floor((1 - Math.asinh(Math.tan(lat * Math.PI / 180)) / Math.PI) / 2 * n)];
};
let seed = 12345;
const rnd = () => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return seed >>> 0; };
async function tile(x, y, noise = false) {
  const bits = new Uint8Array(256 * 256);
  if (noise) for (let i = 0; i < bits.length; i++) bits[i] = rnd() & 1;
  else bits.fill(1, 0, (x + y) % 200 + 1);
  return zlib(bmp1(bits));
}
async function level(z, x0, y0, nx, ny, opts = {}) {
  const tiles = [];
  for (let j = 0; j < ny; j++) {
    for (let i = 0; i < nx; i++) {
      const x = x0 + i, y = y0 + j;
      if (opts.empty && opts.empty.some(([a, b]) => a === x && b === y)) tiles.push(null);
      else tiles.push(await tile(x, y, opts.noiseRow === y));
    }
  }
  return { z, x0, y0, nx, ny, tiles };
}
const meta = (name, bounds, levels, made) => ({ name, bounds, levels, lang: 'local', made, data_date: '2026-10-19',
  source: 'versatiles', attribution: '© OpenStreetMap contributors, VersaTiles', tool: 1 });

const [cx, cy] = tileXY(29.03, 40.99, 15);
const X15 = cx - 2, Y15 = cy - 1;                 // city: 5 x 3 at z15, 10 x 6 at z16
const city = writePack({
  meta: meta('City', [29.0, 40.97, 29.06, 41.01], [15, 16], '2026-11-01'),
  levels: [
    await level(15, X15, Y15, 5, 3),
    await level(16, 2 * X15, 2 * Y15, 10, 6, { empty: [[2 * X15 + 1, 2 * Y15], [2 * X15 + 3, 2 * Y15 + 2]], noiseRow: 2 * Y15 + 4 }),
  ],
  names: [
    { name: 'Kadıköy', kind: 4, lon: 29.0275, lat: 40.9903 },
    { name: 'Moda Caddesi', kind: 6, lon: 29.026, lat: 40.984 },
    { name: 'Haydarpaşa', kind: 7, lon: 29.019, lat: 40.997 },
    { name: 'Fenerbahçe Parkı', kind: 9, lon: 29.037, lat: 40.986 },
  ],
});
const inner = writePack({
  meta: meta('Inner', [29.02, 40.98, 29.04, 41.0], [15, 16, 17], '2026-11-10'),
  levels: [
    await level(15, X15 + 1, Y15 + 1, 2, 1),
    await level(16, 2 * X15 + 2, 2 * Y15 + 2, 4, 2),
    await level(17, 4 * X15 + 4, 4 * Y15 + 4, 8, 4),
  ],
  names: [{ name: 'Moda', kind: 4, lon: 29.025, lat: 40.983 }],
});
const levels = [];
for (let z = 8; z <= 13; z++) {
  const [a, b] = tileXY(28.0, 41.5, z), [c, d] = tileXY(30.0, 40.5, z);
  levels.push(await level(z, a, b, c - a + 1, d - b + 1));
}
const overview = writePack({ meta: meta('Overview', [28.0, 40.5, 30.0, 41.5], [8, 9, 10, 11, 12, 13], '2026-10-01'),
  levels, names: [{ name: 'İstanbul', kind: 1, lon: 28.9784, lat: 41.0082 }] });
const manyNames = [];
for (let i = 0; i < 400; i++) manyNames.push({ name: 'Moda', kind: 6, lon: 29.02 + i / 100, lat: 40.98 });   // 0.01 degree apart: not one place
for (let i = 0; i < 300; i++) manyNames.push({ name: `Aaa ${i}`, kind: 6, lon: 29.02, lat: 40.98 }, { name: `Zzz ${i}`, kind: 6, lon: 29.02, lat: 40.98 });
const many = writePack({ meta: meta('Many', [29.0, 40.97, 29.06, 41.01], [15], '2026-09-01'), levels: [await level(15, X15, Y15, 1, 1)], names: manyNames });
for (const [n, b] of [['city.map', city], ['inner.map', inner], ['overview.map', overview], ['many.map', many]]) writeFileSync(join(out, n), b);
console.log(JSON.stringify({ X15, Y15, city: city.length, inner: inner.length, overview: overview.length }));
