// Where the map maker's vector tiles come from, under which limits. VersaTiles is live: no key, no
// account, CORS open. OpenFreeMap is dormant: its terms want a User-Agent a web page cannot set, so
// it is selectable only with ?source=openfreemap until its maintainer answers (asked 2026-11-15).
// Switching or adding a source changes this file (and, for another schema, schema/<name>.js).

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
    enabled: false,
  },
};

// location.search -> the source to use
export function pickSource(search) {
  const want = new URLSearchParams(search || '').get('source');
  return want === 'openfreemap' ? SOURCES.openfreemap : SOURCES.versatiles;
}
