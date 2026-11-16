// Where the map maker's vector tiles come from, under which limits, and which one a pack uses.
// OpenFreeMap (OpenMapTiles: peaks with heights, more places, weekly data) is used when the pack fits
// what its founder agreed to (2026-11-16): at most 3000 tiles and 50 MB downloaded per pack, every
// tile cached in the browser; the Origin and Referer of the page identify the requests. Larger or
// denser packs come from VersaTiles (Shortbread, no peaks): no key, CORS open. ?source=… forces one.

import { tileRange, vectorZoom, estimate } from './tiles.js';

export const SOURCES = {
  versatiles: {
    id: 'versatiles',
    title: 'VersaTiles',
    schema: 'shortbread',
    tiles: 'https://tiles.versatiles.org/tiles/osm/{z}/{x}/{y}',
    tileJson: 'https://tiles.versatiles.org/tiles/osm/tiles.json',
    maxzoom: 14,
    attribution: '© OpenStreetMap contributors, VersaTiles',
    limits: { maxVectorTiles: 10000, parallel: 4 },
    enabled: true,
  },
  openfreemap: {
    id: 'openfreemap',
    title: 'OpenFreeMap',
    schema: 'openmaptiles',
    tiles: null,                                  // read from the TileJSON (a dated planet build)
    tileJson: 'https://tiles.openfreemap.org/planet',
    maxzoom: 14,
    attribution: '© OpenStreetMap contributors, OpenMapTiles, OpenFreeMap',
    limits: { maxVectorTiles: 3000, maxBytes: 50e6, parallel: 4 },
    enabled: true,
  },
};

// location.search -> the source named by ?source=, or null (choose by the pack)
export function forcedSource(search) {
  const want = new URLSearchParams(search || '').get('source');
  return SOURCES[want] || null;
}

// the bytes a pack downloads, from sampled tile sizes: { top: mean bytes at the deepest vector zoom,
// low: mean bytes two zooms up, used for every shallower zoom }; MapLibre's margins add a quarter
export function downloadEstimate(bbox, levels, sizes) {
  const vzs = [...new Set(levels.map(vectorZoom))], top = Math.max(...vzs);
  let bytes = 0;
  for (const vz of vzs) {
    const r = tileRange(bbox, vz);
    bytes += (r.nx + 2) * (r.ny + 2) * (vz === top ? sizes.top : sizes.low);
  }
  return bytes * 1.25;
}

// up to k x k tiles spread evenly over the area at zoom z
export function samplePoints(bbox, z, k) {
  const r = tileRange(bbox, z), seen = new Set(), out = [];
  for (let i = 0; i < k; i++) {
    for (let j = 0; j < k; j++) {
      const x = r.x0 + Math.floor(((i + 0.5) * r.nx) / k), y = r.y0 + Math.floor(((j + 0.5) * r.ny) / k);
      if (!seen.has(`${x}/${y}`)) { seen.add(`${x}/${y}`); out.push({ z, x, y }); }
    }
  }
  return out;
}

// the share of OpenFreeMap's 50 MB the estimate may fill (a sample can miss the densest corner)
export const BUDGET_SHARE = 0.7;
// the pack's tiles fit OpenFreeMap's 3000, with the estimate's quarter for MapLibre's margins (a run
// fetched 96 for 92 in Moda and 428 for 408 over Uludağ, samples included, 2026-11-16)
export function fitsOpenFreeMap(bbox, levels) {
  return !estimate(bbox, levels, SOURCES.openfreemap.limits).refused;
}

// -> { source, reason: 'forced' | 'too-large' | 'dense' | 'unreachable' | 'fits', download }
// size(source, z, x, y) -> bytes of that tile (the page fetches through the pack's own fetcher, so a
// sampled tile is cached and not fetched again by the run)
export async function chooseSource({ bbox, levels, search, size }) {
  const forced = forcedSource(search);
  if (forced) return { source: forced, reason: 'forced', download: null };
  const ofm = SOURCES.openfreemap, vt = SOURCES.versatiles;
  if (!fitsOpenFreeMap(bbox, levels)) return { source: vt, reason: 'too-large', download: null };
  const vzs = [...new Set(levels.map(vectorZoom))], top = Math.max(...vzs), low = Math.max(Math.min(...vzs), top - 2);
  const mean = async (pts) => (await Promise.all(pts.map((p) => size(ofm, p.z, p.x, p.y)))).reduce((a, b) => a + b, 0) / pts.length;
  let sizes;
  try {
    sizes = { top: await mean(samplePoints(bbox, top, 3)), low: await mean(samplePoints(bbox, low, 2)) };
  } catch {
    return { source: vt, reason: 'unreachable', download: null };
  }
  const download = downloadEstimate(bbox, levels, sizes);
  if (download > ofm.limits.maxBytes * BUDGET_SHARE) return { source: vt, reason: 'dense', download };
  return { source: ofm, reason: 'fits', download };
}

// a run failed with err.code (render.js): 'budget' or 'limit' (OpenFreeMap's per-pack limits ran out)
// or 'source' (the tile server failed: HTTP errors, no connection, tiles that never came) -> the other
// source to start again from, or null. VersaTiles only stands in when the pack fits OpenFreeMap.
export function fallbackSource({ used, code, fitsOfm, forced = null }) {
  if (forced) return null;
  if (used.id === 'openfreemap') return ['budget', 'limit', 'source'].includes(code) ? SOURCES.versatiles : null;
  return code === 'source' && fitsOfm ? SOURCES.openfreemap : null;
}
