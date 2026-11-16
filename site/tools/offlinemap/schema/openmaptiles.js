// The e-ink style and name extraction for OpenMapTiles vector tiles (OpenFreeMap); kept in step with
// shortbread.js by the role tests. It adds peaks with their heights.
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
const PEAKS = ['peak', 'volcano'];
const STATIONS = ['station', 'halt', 'subway'];
const NOT_PLACE = ['continent', 'country', 'state', 'province'];   // Shortbread keeps these out of place labels too
const placeSize = ['match', ['get', 'class'], ['city'], 22, 'town', 18, ['suburb', 'village'], 15, 13];

export function layers({ lang = 'local' } = {}) {
  return [
    background(),
    ...draw.water('water', 'water', null),
    ...draw.forest('forest', 'landcover', cls('wood')),
    // city parks and gardens: landcover subclasses and playgrounds. The park layer is protected areas
    // (national parks, reserves) that cover whole mountains, so it is not drawn
    ...draw.park('park', 'landcover', sub('park', 'garden', 'playground', 'recreation_ground', 'village_green', 'golf_course')),
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

export function nameEntry(sourceLayer, props, geometry, lang) {
  const name = nameOf(props, lang);
  if (!name) return null;
  let k = null;
  if (sourceLayer === 'place') k = NOT_PLACE.includes(props.class) ? null : PLACE[props.class] || 5;
  else if (sourceLayer === 'transportation_name') k = 6;
  else if (sourceLayer === 'mountain_peak') k = PEAKS.includes(props.class) ? 8 : null;
  else if (sourceLayer === 'water_name') k = 10;
  else if (sourceLayer === 'poi') {
    if (props.class === 'railway') k = STATIONS.includes(props.subclass) ? 7 : null;   // not tram stops
    else if (props.class === 'bus') k = null;                                         // stops: too many, as in Shortbread
    else k = props.class === 'park' ? 9 : 11;
  }
  if (!k) return null;
  const at = anchorOf(geometry);
  return at ? { name, kind: k, lon: at[0], lat: at[1] } : null;
}
