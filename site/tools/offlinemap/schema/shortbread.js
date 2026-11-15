// The e-ink style and name extraction for Shortbread 1.0 vector tiles (VersaTiles).
// https://shortbread-tiles.org/schema/1.0/ ; it has no peaks or springs.
import { draw, background, anchorOf, nameOf } from '../eink.js';

export const id = 'shortbread';
export const streetLabelLayer = 'street_labels';   // the lines whose names a route's streets get
export const missing = ['peak'];

const kind = (...k) => ['in', ['get', 'kind'], ['literal', k]];
const not = (f) => ['!', f];
const MAJOR = ['motorway', 'motorway_link', 'trunk', 'trunk_link', 'primary', 'primary_link', 'secondary', 'secondary_link'];
const STREET = ['tertiary', 'tertiary_link', 'unclassified', 'residential', 'living_street', 'pedestrian', 'service', 'busway'];
const PATH = ['footway', 'path', 'track', 'cycleway', 'steps', 'bridleway'];
const RAIL = ['rail', 'light_rail', 'narrow_gauge', 'tram', 'subway', 'funicular', 'monorail'];
const noTunnel = not(['==', ['get', 'tunnel'], true]);

const placeSize = ['match', ['get', 'kind'], ['capital', 'state_capital', 'city'], 22, 'town', 18, ['suburb', 'village'], 15, 13];
const amenity = (...v) => ['in', ['get', 'amenity'], ['literal', v]];
const tourism = (...v) => ['in', ['get', 'tourism'], ['literal', v]];

export function layers({ lang = 'local' } = {}) {
  return [
    background(),
    ...draw.water('ocean', 'ocean', null),
    ...draw.water('water', 'water_polygons', null),
    ...draw.forest('forest', 'land', kind('forest', 'wood')),
    ...draw.park('park', 'land', kind('park', 'garden', 'playground', 'recreation_ground', 'village_green', 'golf_course')),
    ...draw.waterway('waterway', 'water_lines', kind('river', 'canal', 'stream')),
    ...draw.building('building', 'buildings', null),
    ...draw.path('path', 'streets', ['all', kind(...PATH), noTunnel]),
    ...draw.rail('rail', 'streets', ['all', kind(...RAIL), noTunnel]),
    ...draw.street('street', 'streets', ['all', kind(...STREET), noTunnel]),
    ...draw.roadsMajor('major', 'streets', ['all', kind(...MAJOR), noTunnel]),
    ...draw.waterLabel('water-name', 'water_polygons_labels', null, lang),
    ...draw.waterLabel('waterway-name', 'water_lines_labels', null, lang, true),
    ...draw.streetLabel('street-name', 'street_labels', kind(...MAJOR, ...STREET), lang),
    ...draw.poi('station', 'poi-station', 'public_transport', kind('station', 'halt'), 13, lang, true),
    ...draw.poi('bus', 'poi-bus', 'public_transport', kind('bus_stop', 'tram_stop'), 17, lang),
    ...draw.poi('health', 'poi-health', 'pois', amenity('hospital', 'pharmacy', 'clinic'), 16, lang),
    ...draw.poi('toilets', 'poi-toilets', 'pois', amenity('toilets'), 16, lang),
    ...draw.poi('museum', 'poi-museum', 'pois', tourism('museum'), 15, lang, true),
    ...draw.poi('viewpoint', 'poi-viewpoint', 'pois', tourism('viewpoint'), 15, lang),
    ...draw.poi('drinking-water', 'poi-water', 'pois', amenity('drinking_water', 'water_point'), 15, lang),
    ...draw.poi('shelter', 'poi-shelter', 'pois', amenity('shelter'), 15, lang),
    ...draw.poi('camp', 'poi-camp', 'pois', tourism('camp_site'), 14, lang, true),
    ...draw.poi('hut', 'poi-hut', 'pois', tourism('alpine_hut', 'wilderness_hut'), 14, lang, true),
    ...draw.placeLabel('place', 'place_labels', null, lang, placeSize),
  ];
}

export const nameLayers = ['place_labels', 'street_labels', 'public_transport', 'pois', 'water_polygons_labels', 'water_lines_labels'];

const PLACE = { capital: 1, state_capital: 1, city: 1, town: 2, village: 3, suburb: 4, quarter: 4, neighbourhood: 4 };
const POI_KEYS = ['amenity', 'tourism', 'leisure', 'historic', 'man_made', 'shop'];

// a feature from a name layer -> { name, kind, lon, lat } or null
export function nameEntry(sourceLayer, props, geometry, lang) {
  const name = nameOf(props, lang);
  if (!name) return null;
  let k = null;
  if (sourceLayer === 'place_labels') k = PLACE[props.kind] || 5;
  else if (sourceLayer === 'street_labels') k = 6;
  else if (sourceLayer === 'public_transport') k = (props.kind === 'station' || props.kind === 'halt') ? 7 : null;
  else if (sourceLayer === 'water_polygons_labels' || sourceLayer === 'water_lines_labels') k = 10;
  else if (sourceLayer === 'pois') {
    if (props.leisure === 'park' || props.leisure === 'garden' || props.leisure === 'nature_reserve') k = 9;
    else if (POI_KEYS.some((key) => props[key])) k = 11;
  }
  if (!k) return null;
  const at = anchorOf(geometry);
  return at ? { name, kind: k, lon: at[0], lat: at[1] } : null;
}
