// Tile math for the map maker: Web Mercator XYZ tiles of 256 px, the detail presets, and the
// estimate shown before a pack is made (tiles, vector tiles to fetch, size range, time, refusal).

export const PRESETS = {
  overview: [8, 9, 10, 11, 12, 13],
  streets: [10, 11, 12, 13, 14, 15, 16, 17],
  closeup: [10, 11, 12, 13, 14, 15, 16, 17, 18, 19],
};

export function lonLatToTile(lon, lat, z) {
  const n = 2 ** z;
  const r = (Math.max(-85.0511, Math.min(85.0511, lat)) * Math.PI) / 180;
  return { x: ((lon + 180) / 360) * n, y: ((1 - Math.asinh(Math.tan(r)) / Math.PI) / 2) * n };
}

export function tileToLonLat(x, y, z) {
  const n = 2 ** z;
  return { lon: (x / n) * 360 - 180, lat: (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / n))) * 180) / Math.PI };
}

// bbox [west, south, east, north] -> the tiles covering it at z
export function tileRange([w, s, e, n], z) {
  const a = lonLatToTile(w, n, z), b = lonLatToTile(e, s, z);
  const max = 2 ** z - 1;
  const x0 = Math.max(0, Math.floor(a.x)), y0 = Math.max(0, Math.floor(a.y));
  const x1 = Math.min(max, Math.floor(b.x)), y1 = Math.min(max, Math.floor(b.y));
  return { x0, y0, nx: x1 - x0 + 1, ny: y1 - y0 + 1 };
}

// MapLibre's vector sources use 512 px tiles: output level z is map zoom z - 1
export const vectorZoom = (z) => Math.min(z - 1, 14);

// the vector tiles a pack needs: per distinct vector zoom, the range with one tile of margin
export function vectorTiles(bbox, levels) {
  let n = 0;
  for (const vz of new Set(levels.map(vectorZoom))) {
    const r = tileRange(bbox, vz);
    n += (r.nx + 2) * (r.ny + 2);
  }
  return n;
}

// output tiles per pack: the browser holds the whole pack in memory while making it (my call)
export const MAX_TILES = 50000;

const KB = 1024;
const perTileHigh = (z) => (z <= 16 ? 5 : z === 17 ? 3.5 : z === 18 ? 2.5 : 2) * KB;   // a dense city (Kadıköy, 2026-11-15)
const PER_TILE_LOW = 0.6 * KB;                                                            // countryside

// -> { tiles, vectorTiles, bytesLow, bytesHigh, seconds, refused, advice }
export function estimate(bbox, levels, limits) {
  let tiles = 0, bytesHigh = 0;
  for (const z of levels) {
    const r = tileRange(bbox, z);
    tiles += r.nx * r.ny;
    bytesHigh += r.nx * r.ny * perTileHigh(z);
  }
  const vt = vectorTiles(bbox, levels);
  const bytesLow = tiles * PER_TILE_LOW;
  let refused = null;
  // MapLibre also fetches the tiles around each view: about a quarter more than the area needs
  if (tiles > MAX_TILES) refused = 'tiles';
  else if (vt * 1.25 > limits.maxVectorTiles) refused = 'vector-tiles';
  let advice = '';
  if (refused) {
    const less = levels.at(-1) > 13 ? ' or less detail (Overview)' : '';
    advice = refused === 'tiles'
      ? `This would be ${tiles.toLocaleString('en')} tiles, more than the ${MAX_TILES.toLocaleString('en')} one pack can hold. Choose a smaller area${less}; a big area can be several packs.`
      : `This needs ${vt.toLocaleString('en')} map tiles from the data source, more than the ${limits.maxVectorTiles.toLocaleString('en')} one pack may use. Choose a smaller area${less || ' (Overview is already the least detail)'}; a big area can be several packs.`;
  }
  return { tiles, vectorTiles: vt, bytesLow, bytesHigh, seconds: tiles * 0.03 + vt * 0.03, refused, advice };
}
