// The e-ink style and name extraction for Shortbread 1.0 vector tiles (VersaTiles).
// https://shortbread-tiles.org/schema/1.0/ ; it has no peaks or springs.
import { draw, background, anchorOf, nameOf, nearOf, nearFeature } from '../eink.js';

export const id = 'shortbread';
export const streetLabelLayer = 'street_labels';   // the lines whose names a route's streets get
export const missing = ['peak'];

const kind = (...k) => ['in', ['get', 'kind'], ['literal', k]];
const not = (f) => ['!', f];
const MAJOR = ['motorway', 'motorway_link', 'trunk', 'trunk_link', 'primary', 'primary_link', 'secondary', 'secondary_link'];
const STREET = ['tertiary', 'tertiary_link', 'unclassified', 'residential', 'living_street', 'pedestrian', 'service', 'busway'];
const PARKS = ['park', 'garden', 'playground', 'recreation_ground', 'village_green', 'golf_course'];
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
    ...draw.park('park', 'land', kind(...PARKS)),
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

// a feature of a name layer -> its search kind from its properties, or null
export function nameKind(sourceLayer, props) {
  if (sourceLayer === 'place_labels') return PLACE[props.kind] || 5;
  if (sourceLayer === 'street_labels') return 6;
  if (sourceLayer === 'public_transport') return (props.kind === 'station' || props.kind === 'halt') ? 7 : null;
  if (sourceLayer === 'water_polygons_labels' || sourceLayer === 'water_lines_labels') return 10;
  if (sourceLayer === 'pois') {
    if (props.leisure === 'park' || props.leisure === 'garden' || props.leisure === 'nature_reserve') return 9;
    if (POI_KEYS.some((key) => props[key])) return 11;
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
// lines; places and stations as points; lakes (10) and city parks (9) as areas, named by their
// labels (site/tools/offlinemap/near.js nameAreas)
export const nearLayers = ['place_labels', 'street_labels', 'public_transport', 'water_lines_labels'];
export const areaLayers = ['water_polygons', 'land'];
export function nearKind(sourceLayer, props) {
  if (sourceLayer === 'street_labels') return MAJOR.includes(props.kind) || STREET.includes(props.kind) ? 6 : PATH.includes(props.kind) ? 12 : null;
  if (sourceLayer === 'water_lines_labels') return 13;
  return nearOf(sourceLayer, props, nameKind);
}
export function nearEntry(sourceLayer, props, geometry, lang) { return nearFeature(nearKind(sourceLayer, props), props, geometry, lang); }
export function areaKind(sourceLayer, props) {
  if (sourceLayer === 'water_polygons') return 10;
  if (sourceLayer === 'land') return PARKS.includes(props.kind) ? 9 : null;
  return null;
}
