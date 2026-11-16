// The e-ink style and name extraction for OpenMapTiles vector tiles (OpenFreeMap); kept in step with
// shortbread.js by the role tests. It adds peaks with their heights.
// https://openmaptiles.org/schema/
import { draw, background, anchorOf, nameOf, nearOf, nearFeature } from '../eink.js';

export const id = 'openmaptiles';
export const streetLabelLayer = 'transportation_name';   // the lines whose names a route's streets get
export const missing = [];

const cls = (...c) => ['in', ['get', 'class'], ['literal', c]];
const sub = (...c) => ['in', ['get', 'subclass'], ['literal', c]];
const noTunnel = ['!=', ['get', 'brunnel'], 'tunnel'];
const MAJOR = ['motorway', 'trunk', 'primary', 'secondary'];
const STREET = ['tertiary', 'minor', 'service', 'busway'];
const PEAKS = ['peak', 'volcano'];
const STATIONS = ['station', 'halt', 'subway'];
const PARKS = ['park', 'garden', 'playground', 'recreation_ground', 'village_green', 'golf_course'];
const NOT_PLACE = ['continent', 'country', 'state', 'province'];   // Shortbread keeps these out of place labels too
const placeSize = ['match', ['get', 'class'], ['city'], 22, 'town', 18, ['suburb', 'village'], 15, 13];

export function layers({ lang = 'local' } = {}) {
  return [
    background(),
    ...draw.water('water', 'water', null),
    ...draw.forest('forest', 'landcover', cls('wood')),
    // city parks and gardens: landcover subclasses and playgrounds. The park layer is protected areas
    // (national parks, reserves) that cover whole mountains, so it is not drawn
    ...draw.park('park', 'landcover', sub(...PARKS)),
    ...draw.park('park-play', 'landuse', cls('playground')),
    ...draw.waterway('waterway', 'waterway', cls('river', 'canal', 'stream')),
    ...draw.building('building', 'building', null),
    ...draw.path('path', 'transportation', ['all', cls('path', 'track'), noTunnel]),
    ...draw.rail('rail', 'transportation', ['all', cls('rail', 'transit'), noTunnel]),
    ...draw.street('street', 'transportation', ['all', cls(...STREET), noTunnel]),
    ...draw.roadsMajor('major', 'transportation', ['all', cls(...MAJOR), noTunnel]),
    ...draw.waterLabel('water-name', 'water_name', null, lang),
    ...draw.streetLabel('street-name', 'transportation_name', cls(...MAJOR, ...STREET), lang),
    // tram stops and subway stations come as class railway here (Shortbread: tram_stop with bus_stop)
    ...draw.poi('station', 'poi-station', 'poi', ['all', cls('railway'), sub(...STATIONS)], 13, lang, true),
    ...draw.poi('bus', 'poi-bus', 'poi', ['any', cls('bus'), sub('tram_stop')], 17, lang),
    ...draw.poi('health', 'poi-health', 'poi', cls('hospital', 'pharmacy'), 16, lang),
    ...draw.poi('toilets', 'poi-toilets', 'poi', cls('toilets'), 16, lang),
    ...draw.poi('museum', 'poi-museum', 'poi', cls('museum'), 15, lang, true),
    ...draw.poi('viewpoint', 'poi-viewpoint', 'poi', sub('viewpoint'), 15, lang),
    ...draw.poi('drinking-water', 'poi-water', 'poi', cls('drinking_water'), 15, lang),
    ...draw.poi('shelter', 'poi-shelter', 'poi', cls('shelter'), 15, lang),
    ...draw.poi('camp', 'poi-camp', 'poi', cls('campsite'), 14, lang, true),
    ...draw.poi('hut', 'poi-hut', 'poi', sub('alpine_hut', 'wilderness_hut'), 14, lang, true),
    ...draw.peak('peak', 'mountain_peak', cls(...PEAKS), 13, lang),
    ...draw.placeLabel('place', 'place', ['!', cls(...NOT_PLACE)], lang, placeSize),
  ];
}

export const nameLayers = ['place', 'transportation_name', 'poi', 'mountain_peak', 'water_name'];

const PLACE = { city: 1, town: 2, village: 3, suburb: 4, quarter: 4, neighbourhood: 4 };

// a feature of a name layer -> its search kind from its properties, or null
export function nameKind(sourceLayer, props) {
  if (sourceLayer === 'place') return NOT_PLACE.includes(props.class) ? null : PLACE[props.class] || 5;
  if (sourceLayer === 'transportation_name') return 6;
  if (sourceLayer === 'mountain_peak') return PEAKS.includes(props.class) ? 8 : null;
  if (sourceLayer === 'water_name') return 10;
  if (sourceLayer === 'poi') {
    if (props.class === 'railway') return STATIONS.includes(props.subclass) ? 7 : null;   // not tram stops
    if (props.class === 'bus') return null;                                              // stops: too many, as in Shortbread
    return props.class === 'park' ? 9 : 11;
  }
  return null;
}

// a feature from a name layer -> { name, kind, lon, lat } or null
export function nameEntry(sourceLayer, props, geometry, lang) {
  const name = nameOf(props, lang), k = name && nameKind(sourceLayer, props);
  if (!k) return null;
  const at = anchorOf(geometry);
  return at ? { name, kind: k, lon: at[0], lat: at[1] } : null;
}

// what a long press on the map names (src/near.lua): streets (6), paths (12) and rivers (13) as
// lines; places, stations and peaks as points; lakes (10) and city parks (9) as areas, named by
// their labels (site/tools/offlinemap/near.js nameAreas)
export const nearLayers = ['place', 'transportation_name', 'poi', 'mountain_peak', 'waterway'];
export const areaLayers = ['water', 'landcover', 'landuse'];
export function nearKind(sourceLayer, props) {
  if (sourceLayer === 'transportation_name') return MAJOR.includes(props.class) || STREET.includes(props.class) ? 6 : ['path', 'track'].includes(props.class) ? 12 : null;
  if (sourceLayer === 'waterway') return 13;
  return nearOf(sourceLayer, props, nameKind);
}
export function nearEntry(sourceLayer, props, geometry, lang) { return nearFeature(nearKind(sourceLayer, props), props, geometry, lang); }
export function areaKind(sourceLayer, props) {
  if (sourceLayer === 'water') return 10;
  if (sourceLayer === 'landcover') return PARKS.includes(props.subclass) ? 9 : null;
  if (sourceLayer === 'landuse') return props.class === 'playground' ? 9 : null;
  return null;
}
