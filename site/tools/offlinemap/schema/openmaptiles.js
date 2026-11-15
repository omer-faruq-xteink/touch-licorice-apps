// The e-ink style and name extraction for OpenMapTiles vector tiles (OpenFreeMap). Dormant until
// OpenFreeMap answers (see ../sources.js); kept in step with shortbread.js by the role tests.
// https://openmaptiles.org/schema/
import { draw, background, anchorOf, nameOf } from '../eink.js';

export const id = 'openmaptiles';
export const streetLabelLayer = 'transportation_name';   // the lines whose names a route's streets get
export const missing = [];

const cls = (...c) => ['in', ['get', 'class'], ['literal', c]];
const sub = (...c) => ['in', ['get', 'subclass'], ['literal', c]];
const noTunnel = ['!=', ['get', 'brunnel'], 'tunnel'];
const MAJOR = ['motorway', 'trunk', 'primary', 'secondary'];
const STREET = ['tertiary', 'minor', 'service', 'busway'];
const placeSize = ['match', ['get', 'class'], ['city'], 22, 'town', 18, ['suburb', 'village'], 15, 13];

export function layers({ lang = 'local' } = {}) {
  return [
    background(),
    ...draw.water('water', 'water', null),
    ...draw.forest('forest', 'landcover', cls('wood')),
    ...draw.park('park', 'park', null),
    ...draw.waterway('waterway', 'waterway', cls('river', 'canal', 'stream')),
    ...draw.building('building', 'building', null),
    ...draw.path('path', 'transportation', ['all', cls('path', 'track'), noTunnel]),
    ...draw.rail('rail', 'transportation', ['all', cls('rail', 'transit'), noTunnel]),
    ...draw.street('street', 'transportation', ['all', cls(...STREET), noTunnel]),
    ...draw.roadsMajor('major', 'transportation', ['all', cls(...MAJOR), noTunnel]),
    ...draw.waterLabel('water-name', 'water_name', null, lang),
    ...draw.streetLabel('street-name', 'transportation_name', cls(...MAJOR, ...STREET), lang),
    ...draw.poi('station', 'poi-station', 'poi', ['all', cls('railway'), sub('station', 'halt')], 13, lang, true),
    ...draw.poi('bus', 'poi-bus', 'poi', cls('bus'), 17, lang),
    ...draw.poi('health', 'poi-health', 'poi', cls('hospital', 'pharmacy'), 16, lang),
    ...draw.poi('toilets', 'poi-toilets', 'poi', cls('toilets'), 16, lang),
    ...draw.poi('museum', 'poi-museum', 'poi', cls('museum'), 15, lang, true),
    ...draw.poi('viewpoint', 'poi-viewpoint', 'poi', sub('viewpoint'), 15, lang),
    ...draw.poi('drinking-water', 'poi-water', 'poi', cls('drinking_water'), 15, lang),
    ...draw.poi('shelter', 'poi-shelter', 'poi', cls('shelter'), 15, lang),
    ...draw.poi('camp', 'poi-camp', 'poi', cls('campsite'), 14, lang, true),
    ...draw.poi('hut', 'poi-hut', 'poi', sub('alpine_hut', 'wilderness_hut'), 14, lang, true),
    ...draw.poi('peak', 'peak', 'mountain_peak', null, 13, lang, true),
    ...draw.placeLabel('place', 'place', null, lang, placeSize),
  ];
}

export const nameLayers = ['place', 'transportation_name', 'poi', 'mountain_peak', 'water_name'];

const PLACE = { city: 1, town: 2, village: 3, suburb: 4, quarter: 4, neighbourhood: 4 };

export function nameEntry(sourceLayer, props, geometry, lang) {
  const name = nameOf(props, lang);
  if (!name) return null;
  let k = null;
  if (sourceLayer === 'place') k = PLACE[props.class] || 5;
  else if (sourceLayer === 'transportation_name') k = 6;
  else if (sourceLayer === 'mountain_peak') k = 8;
  else if (sourceLayer === 'water_name') k = 10;
  else if (sourceLayer === 'poi') k = props.class === 'railway' ? 7 : props.class === 'park' ? 9 : 11;
  if (!k) return null;
  const at = anchorOf(geometry);
  return at ? { name, kind: k, lon: at[0], lat: at[1] } : null;
}
