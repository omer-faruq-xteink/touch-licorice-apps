// The e-ink map style, apart from any data provider: the drawing roles, black on white only, and
// builders the schemas (schema/*.js) call with their own source layers and filters. Patterns stand
// in for grey; symbols are small 1-bit pictures added at render time (no sprite file).
// Zooms here are output levels (256 px tiles); MapLibre's map zoom is one less (512 px tiles).

export const ROLES = ['water', 'water-edge', 'waterway', 'forest', 'park', 'building', 'road-major-casing', 'road-major',
  'road-street', 'path', 'rail', 'place-label', 'street-label', 'water-label', 'poi-station', 'poi-bus', 'poi-health',
  'poi-toilets', 'poi-museum', 'poi-viewpoint', 'poi-water', 'poi-shelter', 'poi-camp', 'poi-hut', 'peak'];

export const GLYPHS = 'https://tiles.versatiles.org/assets/glyphs/{fontstack}/{range}.pbf';
const FONT = ['noto_sans_regular'];
const BOLD = ['noto_sans_bold'];
const B = '#000', W = '#fff';

const mz = (z) => z - 1;                                   // output level -> map zoom
const byZoom = (stops) => ['interpolate', ['exponential', 1.6], ['zoom'], ...stops.flatMap(([z, v]) => [mz(z), v])];

export const textField = (lang) => (lang === 'en' ? ['coalesce', ['get', 'name_en'], ['get', 'name']] : ['get', 'name']);

function layer(id, role, type, sourceLayer, filter, rest) {
  const l = { id, type, source: 'xt', 'source-layer': sourceLayer, metadata: { 'xt:role': role }, ...rest };
  if (filter) l.filter = filter;
  if (rest.minzoom !== undefined) l.minzoom = mz(rest.minzoom);
  return l;
}

export const background = () => ({ id: 'paper', type: 'background', paint: { 'background-color': W } });

// each builder returns a list of layers
export const draw = {
  water: (id, sl, filter) => [
    layer(`${id}-fill`, 'water', 'fill', sl, filter, { paint: { 'fill-pattern': 'xt-water' } }),
    layer(`${id}-edge`, 'water-edge', 'line', sl, filter, { paint: { 'line-color': B, 'line-width': 1 } }),
  ],
  waterway: (id, sl, filter) => [layer(id, 'waterway', 'line', sl, filter,
    { paint: { 'line-color': B, 'line-width': byZoom([[10, 1], [14, 1.5], [18, 4]]) } })],
  forest: (id, sl, filter) => [layer(id, 'forest', 'fill', sl, filter, { paint: { 'fill-pattern': 'xt-forest' } })],
  park: (id, sl, filter) => [layer(id, 'park', 'fill', sl, filter, { paint: { 'fill-pattern': 'xt-park' } })],
  building: (id, sl, filter) => [layer(id, 'building', 'line', sl, filter,
    { minzoom: 16, paint: { 'line-color': B, 'line-width': 1 } })],
  roadsMajor: (id, sl, filter) => [
    layer(`${id}-casing`, 'road-major-casing', 'line', sl, filter, { layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': B, 'line-width': byZoom([[8, 1.5], [12, 3], [15, 8], [17, 16], [19, 40]]) } }),
    layer(id, 'road-major', 'line', sl, filter, { minzoom: 12, layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': W, 'line-width': byZoom([[12, 1], [15, 5], [17, 12], [19, 34]]) } }),
  ],
  street: (id, sl, filter, minzoom = 12) => [layer(id, 'road-street', 'line', sl, filter, { minzoom,
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': B, 'line-width': byZoom([[12, 0.8], [15, 1.5], [17, 3], [19, 8]]) } })],
  path: (id, sl, filter) => [layer(id, 'path', 'line', sl, filter, { minzoom: 13,
    paint: { 'line-color': B, 'line-width': byZoom([[13, 1], [17, 1.5], [19, 2.5]]), 'line-dasharray': [3, 2] } })],
  rail: (id, sl, filter) => [
    layer(id, 'rail', 'line', sl, filter, { minzoom: 10, paint: { 'line-color': B, 'line-width': 1 } }),
    layer(`${id}-ties`, 'rail', 'line', sl, filter, { minzoom: 14,
      paint: { 'line-color': B, 'line-width': byZoom([[14, 4], [19, 8]]), 'line-dasharray': [0.3, 3] } }),
  ],
  placeLabel: (id, sl, filter, lang, size) => [layer(id, 'place-label', 'symbol', sl, filter, {
    layout: { 'text-field': textField(lang), 'text-font': BOLD, 'text-size': size, 'text-max-width': 8, 'text-padding': 4 },
    paint: { 'text-color': B, 'text-halo-color': W, 'text-halo-width': 2.5 } })],
  streetLabel: (id, sl, filter, lang) => [layer(id, 'street-label', 'symbol', sl, filter, { minzoom: 15,
    layout: { 'text-field': textField(lang), 'text-font': FONT, 'symbol-placement': 'line', 'text-size': byZoom([[15, 11], [17, 14], [19, 17]]),
      'symbol-spacing': 300, 'text-padding': 2 },
    paint: { 'text-color': B, 'text-halo-color': W, 'text-halo-width': 2 } })],
  waterLabel: (id, sl, filter, lang, line = false) => [layer(id, 'water-label', 'symbol', sl, filter, { minzoom: 12,
    layout: { 'text-field': textField(lang), 'text-font': FONT, 'text-size': 13, ...(line ? { 'symbol-placement': 'line' } : {}) },
    paint: { 'text-color': B, 'text-halo-color': W, 'text-halo-width': 2 } })],
  poi: (id, role, sl, filter, minzoom, lang, withName = false) => [layer(id, role, 'symbol', sl, filter, { minzoom,
    layout: { 'icon-image': `xt-${role}`, 'icon-allow-overlap': false, 'icon-padding': 2,
      ...(withName ? { 'text-field': textField(lang), 'text-font': FONT, 'text-size': 12, 'text-offset': [0, 1.2], 'text-anchor': 'top', 'text-optional': true } : {}) },
    paint: withName ? { 'text-color': B, 'text-halo-color': W, 'text-halo-width': 2 } : {} })],
};

// ------------------------------------------------------------------ pictures (1-bit, RGBA)

const S = 18;              // symbol size in output pixels
function rgba(w, h, at) {  // at(x, y) -> 'b' black, 'w' white, null transparent
  const data = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const c = at(x, y);
      if (!c) continue;
      const i = 4 * (y * w + x);
      const v = c === 'b' ? 0 : 255;
      data[i] = data[i + 1] = data[i + 2] = v;
      data[i + 3] = 255;
    }
  }
  return { width: w, height: h, data };
}
const c0 = (S - 1) / 2;
const SHAPES = {
  'poi-station': (x, y) => Math.abs(x - c0) <= 6 && Math.abs(y - c0) <= 6 && !(Math.abs(x - c0) <= 3 && Math.abs(y - c0) <= 3 && y < c0),
  'poi-bus': (x, y) => Math.abs(x - c0) <= 4 && Math.abs(y - c0) <= 4,
  'poi-health': (x, y) => (Math.abs(x - c0) <= 1.5 && Math.abs(y - c0) <= 6) || (Math.abs(y - c0) <= 1.5 && Math.abs(x - c0) <= 6),
  'poi-toilets': (x, y) => { const d = Math.hypot(x - c0, y - c0); return d <= 6 && d >= 4; },
  'poi-museum': (x, y) => (y >= c0 + 3 && y <= c0 + 5 && Math.abs(x - c0) <= 6) || (y <= c0 - 2 && y >= c0 - 7 + Math.abs(x - c0) && Math.abs(x - c0) <= 6) || (y > c0 - 2 && y < c0 + 3 && Math.abs(x - c0) % 4 < 1.5 && Math.abs(x - c0) <= 6),
  'poi-viewpoint': (x, y) => { const d = Math.hypot(x - c0, y - c0); return d <= 2.5 || (d >= 5 && d <= 6.5); },
  'poi-water': (x, y) => Math.hypot(x - c0, y - c0 - 1.5) <= 4 || (y < c0 && Math.abs(x - c0) <= (y - (c0 - 6)) * 0.6),
  'poi-shelter': (x, y) => (y >= c0 - 6 + Math.abs(x - c0) && y <= c0 - 4 + Math.abs(x - c0) && Math.abs(x - c0) <= 7) || (Math.abs(Math.abs(x - c0) - 5) <= 1 && y >= c0 - 1 && y <= c0 + 6),
  'poi-camp': (x, y) => y >= c0 - 6 + 1.6 * Math.abs(x - c0) && y <= c0 + 5,
  'poi-hut': (x, y) => (y >= c0 - 7 + Math.abs(x - c0) && y <= c0 && Math.abs(x - c0) <= 7) || (y > c0 && y <= c0 + 6 && Math.abs(x - c0) <= 5),
  peak: (x, y) => y >= c0 - 6 + 1.3 * Math.abs(x - c0) && y <= c0 + 5,
};
export function symbolImage(role) {
  const f = SHAPES[role];
  const black = (x, y) => x >= 0 && y >= 0 && x < S && y < S && f(x, y);
  return rgba(S, S, (x, y) => {
    if (black(x, y)) return 'b';
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) if (black(x + dx, y + dy)) return 'w';   // a halo
    return null;
  });
}
export const SYMBOL_ROLES = Object.keys(SHAPES);

const PATTERNS = {
  water: { size: 6, at: (x, y) => y % 3 === 0 },                                   // horizontal lines
  park: { size: 8, at: (x, y) => x % 8 === 0 && y % 8 === 0 },                    // sparse dots
  forest: { size: 8, at: (x, y) => (x % 8 === 0 && y % 8 === 0) || (x % 8 === 4 && y % 8 === 4) || (x % 8 === 5 && y % 8 === 4) },
};
export function patternImage(name) {
  const p = PATTERNS[name];
  return rgba(p.size, p.size, (x, y) => (p.at(x, y) ? 'b' : 'w'));
}
export const PATTERN_NAMES = Object.keys(PATTERNS);

// a picture at twice the size (MapLibre renders at pixelRatio 2; the result is halved again)
export function doubled(img) {
  const w = img.width * 2, h = img.height * 2, data = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const s = 4 * ((y >> 1) * img.width + (x >> 1)), d = 4 * (y * w + x);
    data[d] = img.data[s]; data[d + 1] = img.data[s + 1]; data[d + 2] = img.data[s + 2]; data[d + 3] = img.data[s + 3];
  }
  return { width: w, height: h, data };
}

// the geometry point a name sits at: a point, the middle of a line's longest part, a ring's mean
export function anchorOf(g) {
  if (!g) return null;
  if (g.type === 'Point') return g.coordinates;
  if (g.type === 'MultiPoint') return g.coordinates[0];
  const longest = (parts) => parts.reduce((a, b) => (b.length > a.length ? b : a), parts[0] || []);
  if (g.type === 'LineString') return g.coordinates[g.coordinates.length >> 1];
  if (g.type === 'MultiLineString') { const p = longest(g.coordinates); return p[p.length >> 1]; }
  const ring = g.type === 'Polygon' ? g.coordinates[0] : g.type === 'MultiPolygon' ? longest(g.coordinates.map((p) => p[0])) : null;
  if (!ring || !ring.length) return null;
  let x = 0, y = 0;
  for (const [a, b] of ring) { x += a; y += b; }
  return [x / ring.length, y / ring.length];
}
export const nameOf = (props, lang) => (lang === 'en' && props.name_en) || props.name || null;
