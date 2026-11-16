// The map maker page, in two modes chosen under the map: a map pack (choose an area and a detail,
// see the estimate, make it with progress and Cancel, copy it to the card) or a route (click it or load
// a GPX, drag its points, look up the names of the streets it follows, copy the GPX to the card).
import { chrome, download, message, bytesText, esc } from '../../assets/site.js';
import { canCopy, card } from '../../assets/store.js';
import { PRESETS, estimate } from './tiles.js';
import { SOURCES, forcedSource, chooseSource, fitsOpenFreeMap, fallbackSource } from './sources.js';
import { TileFetcher } from './fetcher.js';
import { renderPack, makeRouteGpx } from './render.js';
import { lengthM, bboxWithMargin, parseGpx } from './route.js';

const APP = 'offlinemap';
const $ = (id) => document.getElementById(id);
chrome('offlinemap');

// a pack's source is chosen when it is made (sources.js); ?source=versatiles|openfreemap forces one
const forced = forcedSource(location.search);
const schemas = {};
const schemaOf = async (src) => (schemas[src.id] ||= await import(`./schema/${src.schema}.js`));
const routeSource = forced || SOURCES.versatiles;   // a route only needs street names: VersaTiles (my call)
const maplibregl = window.maplibregl;
let bbox = null, packed = null, run = null, lastSearch = 0;
let route = [], routeGpx = null;                  // route: [[lon, lat]]

$('credits').innerHTML = `Map data © OpenStreetMap contributors (<a href="https://www.openstreetmap.org/copyright">ODbL</a>),
  vector tiles from <a href="https://openfreemap.org/">OpenFreeMap</a> (OpenMapTiles) for packs that fit its limits and
  <a href="https://versatiles.org/">VersaTiles</a> for larger or denser ones and for routes,
  drawn with <a href="https://maplibre.org/">MapLibre GL JS</a> (BSD); place search by
  <a href="https://nominatim.org/">Nominatim</a>. Nothing is uploaded: everything is made in this browser.`;

// ------------------------------------------------------------------ the map
const map = new maplibregl.Map({
  container: 'map', style: 'https://tiles.versatiles.org/assets/styles/colorful/style.json',
  center: [28.98, 41.02], zoom: 10, attributionControl: { compact: true },
});
map.addControl(new maplibregl.NavigationControl({ showCompass: false }));
const rectGeo = (b) => ({ type: 'FeatureCollection', features: b ? [{ type: 'Feature', properties: {},
  geometry: { type: 'Polygon', coordinates: [[[b[0], b[1]], [b[2], b[1]], [b[2], b[3]], [b[0], b[3]], [b[0], b[1]]]] } }] : [] });
function routeGeo() {
  const f = route.map((p, i) => ({ type: 'Feature', properties: { i }, geometry: { type: 'Point', coordinates: p } }));
  if (route.length >= 2) f.push({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: route } });
  // a faint point in the middle of each piece: drag it to add a point there
  for (let i = 1; i < route.length; i++) {
    const [a, b] = [route[i - 1], route[i]];
    f.push({ type: 'Feature', properties: { mid: i }, geometry: { type: 'Point', coordinates: [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2] } });
  }
  return { type: 'FeatureCollection', features: f };
}
map.on('load', () => {
  map.addSource('area', { type: 'geojson', data: rectGeo(bbox) });
  map.addLayer({ id: 'area-fill', type: 'fill', source: 'area', paint: { 'fill-color': '#000', 'fill-opacity': 0.08 } });
  map.addLayer({ id: 'area-line', type: 'line', source: 'area', paint: { 'line-color': '#000', 'line-width': 2 } });
  map.addSource('route', { type: 'geojson', data: routeGeo() });
  map.addLayer({ id: 'route-line', type: 'line', source: 'route', filter: ['==', ['geometry-type'], 'LineString'],
    paint: { 'line-color': '#c00', 'line-width': 4 } });
  map.addLayer({ id: 'route-mid', type: 'circle', source: 'route', filter: ['has', 'mid'],
    paint: { 'circle-radius': 4, 'circle-color': '#fff', 'circle-opacity': 0.8, 'circle-stroke-color': '#c00', 'circle-stroke-width': 1, 'circle-stroke-opacity': 0.6 } });
  map.addLayer({ id: 'route-pts', type: 'circle', source: 'route', filter: ['has', 'i'],
    paint: { 'circle-radius': 6, 'circle-color': '#fff', 'circle-stroke-color': '#c00', 'circle-stroke-width': 2 } });
});

// ------------------------------------------------------------------ modes
const mode = () => document.querySelector('input[name=mode]:checked').value;
function setMode() {
  const m = mode();
  $('mapsteps').hidden = m !== 'map';
  $('routesteps').hidden = m !== 'route';
  setDrawing(false);
  setRouting(false);
  map.setLayoutProperty('route-line', 'visibility', 'visible');
}
for (const r of document.querySelectorAll('input[name=mode]')) r.addEventListener('change', () => { if (map.loaded()) setMode(); else map.once('load', setMode); });

// ------------------------------------------------------------------ a map pack: the area
function setArea(b) {
  bbox = b ? [Math.min(b[0], b[2]), Math.min(b[1], b[3]), Math.max(b[0], b[2]), Math.max(b[1], b[3])] : null;
  map.getSource('area')?.setData(rectGeo(bbox));
  if (bbox) {
    const r = Math.PI / 180, mid = (bbox[1] + bbox[3]) / 2;
    const w = (bbox[2] - bbox[0]) * 111.32 * Math.cos(mid * r), h = (bbox[3] - bbox[1]) * 110.57;
    $('area').textContent = `${w.toFixed(1)} × ${h.toFixed(1)} km`;
  } else $('area').textContent = '';
  update();
}
let drawing = false, start = null;
function setDrawing(on) {
  drawing = on;
  start = null;
  $('draw').textContent = on ? 'Drag on the map…' : 'Draw area';
  $('map').classList.toggle('drawing', on || routing);
  if (on) map.dragPan.disable(); else if (!dragging) map.dragPan.enable();
}
$('draw').addEventListener('click', () => setDrawing(!drawing));
$('view').addEventListener('click', () => { const b = map.getBounds(); setArea([b.getWest(), b.getSouth(), b.getEast(), b.getNorth()]); });
$('rarea').addEventListener('click', () => {
  if (route.length < 2) return;
  setArea(bboxWithMargin(route, 500));
  const b = bboxWithMargin(route, 600);
  map.fitBounds([[b[0], b[1]], [b[2], b[3]]], { padding: 20 });
});

// ------------------------------------------------------------------ a route
let routing = false, dragging = null;            // dragging: the index of the point being moved
function setRouting(on) {
  routing = on;
  if (on) map.doubleClickZoom.disable(); else map.doubleClickZoom.enable();   // quick clicks are points, not a zoom
  $('rdraw').textContent = on ? 'Done' : 'Draw route';
  $('map').classList.toggle('drawing', on || drawing);
}
function routeChanged() {
  map.getSource('route')?.setData(routeGeo());
  const has = route.length > 0;
  $('rundo').hidden = !has;
  $('rclear').hidden = !has;
  $('rarea').hidden = route.length < 2;
  $('rmake').disabled = route.length < 2;
  const m = lengthM(route);
  $('rlen').textContent = route.length < 2 ? (has ? 'Click the next point.' : '') :
    `${m < 1000 ? Math.round(m) + ' m' : (m / 1000).toFixed(2) + ' km'}, ${route.length} points; drag a point to move it, or a faint middle point to add one`;
  showRoute(null);
}
$('rdraw').addEventListener('click', () => setRouting(!routing));
$('rundo').addEventListener('click', () => { route.pop(); routeChanged(); });
$('rclear').addEventListener('click', () => { route = []; setRouting(false); routeChanged(); });
$('rfile').addEventListener('change', async () => {
  const f = $('rfile').files[0];
  if (!f) return;
  const g = parseGpx(await f.text());
  $('rfile').value = '';
  if (g.points.length < 2) { $('rlen').textContent = `${f.name}: no track or route points in it.`; return; }
  route = g.points;
  $('rname').value = g.name || f.name.replace(/\.gpx$/i, '');
  setRouting(false);
  routeChanged();
  const b = bboxWithMargin(route, 200);
  map.fitBounds([[b[0], b[1]], [b[2], b[3]]], { padding: 30 });
});

// the mouse on the map: an area being drawn, a route point being dragged, or a new route point
map.on('mousedown', (e) => {
  if (drawing) { start = e.lngLat; e.preventDefault(); return; }
  if (mode() !== 'route' || !map.getLayer('route-pts')) return;
  const hit = map.queryRenderedFeatures(e.point, { layers: ['route-pts'] })[0];
  if (hit) { dragging = hit.properties.i; map.dragPan.disable(); e.preventDefault(); return; }
  const mid = map.queryRenderedFeatures(e.point, { layers: ['route-mid'] })[0];
  if (mid) {                                       // a new point in that piece, dragged from there
    const i = mid.properties.mid;
    route.splice(i, 0, [e.lngLat.lng, e.lngLat.lat]);
    dragging = i;
    map.dragPan.disable();
    e.preventDefault();
  }
});
map.on('mousemove', (e) => {
  if (drawing && start) setArea([start.lng, start.lat, e.lngLat.lng, e.lngLat.lat]);
  else if (dragging !== null) { route[dragging] = [e.lngLat.lng, e.lngLat.lat]; map.getSource('route').setData(routeGeo()); }
  else if (mode() === 'route' && map.getLayer('route-pts')) {
    map.getCanvas().style.cursor = map.queryRenderedFeatures(e.point, { layers: ['route-pts', 'route-mid'] }).length ? 'move' : '';
  }
});
let justDragged = false;
map.on('mouseup', (e) => {
  if (drawing && start) {
    setArea([start.lng, start.lat, e.lngLat.lng, e.lngLat.lat]);
    setDrawing(false);
  } else if (dragging !== null) {
    dragging = null;
    justDragged = true;
    map.dragPan.enable();
    routeChanged();
  }
});
map.on('click', (e) => {
  if (justDragged) { justDragged = false; return; }
  if (routing) { route.push([e.lngLat.lng, e.lngLat.lat]); routeChanged(); }
});

// the made route, offered in the last step
function showRoute(gpx) {
  routeGpx = gpx;
  $('rsave').hidden = !gpx;
  $('noroute').hidden = !!gpx;
  if (!gpx) message($('rsaved'), '');
}
$('rmake').addEventListener('click', async () => {
  if (route.length < 2) return;
  $('rmake').disabled = true;
  showRoute(null);
  message($('rresult'), 'Looking up the streets…');
  try {
    const look = async (src) => makeRouteGpx({ name: $('rname').value.trim() || 'My route', points: route, lang: $('lang').value,
      source: src, schema: await schemaOf(src), maplibregl, fetcher: new TileFetcher(src),
      onProgress: (p) => message($('rresult'), `Looking up the streets… ${p.done} of ${p.total}`) });
    let res;
    try {
      res = await look(routeSource);
    } catch (e) {
      // a route is a few tiles: it always fits OpenFreeMap
      const other = fallbackSource({ used: routeSource, code: e.code, fitsOfm: true, forced });
      if (!other) throw e;
      try { res = await look(other); } catch (e2) { throw new Error(`Both map sources failed. ${routeSource.title}: ${e.message} ${other.title}: ${e2.message}`); }
    }
    const { gpx, labels } = res;
    const names = [...new Set(labels.map((l) => l.name))];
    message($('rresult'), `Done: ${(lengthM(route) / 1000).toFixed(2)} km` + (names.length ? `, along ${names.slice(0, 6).map(esc).join(', ')}${names.length > 6 ? '…' : ''}.` : ', no street names found.'), 'ok');
    showRoute(gpx);
  } catch (e) {
    message($('rresult'), esc(e.message || e), 'err');
  } finally {
    $('rmake').disabled = route.length < 2;
  }
});

// ------------------------------------------------------------------ place search (Nominatim: on request only, at most one a second)
async function find() {
  const q = $('q').value.trim();
  if (!q || Date.now() - lastSearch < 1000) return;
  lastSearch = Date.now();
  $('results').innerHTML = '<li class="note">Searching…</li>';
  try {
    const r = await fetch(`https://nominatim.openstreetmap.org/search?format=json&limit=5&q=${encodeURIComponent(q)}`);
    const list = await r.json();
    $('results').innerHTML = '';
    if (!list.length) $('results').innerHTML = '<li class="note">Nothing found.</li>';
    for (const p of list) {
      const li = document.createElement('li');
      const b = document.createElement('button');
      b.textContent = p.display_name;
      b.addEventListener('click', () => {
        const [s, n, w, e] = p.boundingbox.map(Number);
        map.fitBounds([[w, s], [e, n]], { padding: 30, maxZoom: 15 });
        $('name').value = p.display_name.split(',')[0];
        $('results').innerHTML = '';
      });
      li.append(b);
      $('results').append(li);
    }
  } catch (e) {
    $('results').innerHTML = `<li class="note">Search failed: ${esc(e.message)}</li>`;
  }
}
$('find').addEventListener('click', find);
$('q').addEventListener('keydown', (e) => { if (e.key === 'Enter') find(); });

// ------------------------------------------------------------------ a map pack: estimate, make, save
function showPack(bytes) {
  packed = bytes;
  $('save').hidden = !bytes;
  $('nopack').hidden = !!bytes;
  if (!bytes) message($('saved'), '');
}
const preset = () => document.querySelector('input[name=preset]:checked').value;
const timeText = (s) => (s < 60 ? `${Math.max(1, Math.round(s))} s` : s < 3600 ? `${Math.round(s / 60)} min` : `${(s / 3600).toFixed(1)} h`);
function update() {
  showPack(null);
  if (!bbox) { message($('estimate'), 'Choose an area first.'); $('make').disabled = true; return; }
  const levels = PRESETS[preset()];
  const est = estimate(bbox, levels, (forced || SOURCES.versatiles).limits);
  if (est.refused) { message($('estimate'), esc(est.advice), 'err'); $('make').disabled = true; return; }
  const from = forced ? `Map data from ${forced.title}.`
    : !fitsOpenFreeMap(bbox, levels) ? 'Map data from VersaTiles: the area is too large for OpenFreeMap, so no peaks.'
    : 'Map data from OpenFreeMap, with peaks; from VersaTiles if the area is a dense city (checked when you press Make).';
  message($('estimate'), `${est.tiles.toLocaleString('en')} tiles, about ${bytesText(est.bytesLow)}–${bytesText(est.bytesHigh)} ` +
    `(countryside to dense city), roughly ${timeText(est.seconds)}; ${est.vectorTiles.toLocaleString('en')} map tiles to fetch. ${from}`);
  $('make').disabled = !!run;
}
for (const r of document.querySelectorAll('input[name=preset]')) r.addEventListener('change', update);
$('lang').addEventListener('change', update);
update();

const safeName = (s, ext) => (s.replace(/[\\/:*?"<>|~\x00-\x1f]/g, ' ').replace(/\s+/g, ' ').trim().replace(/^\.+|[. ]+$/g, '') || 'My map').slice(0, 60) + ext;
$('make').addEventListener('click', async () => {
  if (!bbox || run) return;
  showPack(null);
  const ac = new AbortController();
  run = ac;
  $('make').disabled = true;
  $('cancel').hidden = false;
  $('progress').hidden = false;
  $('fill').style.width = '0';
  $('ptext').textContent = 'Starting…';
  message($('result'), '');
  const levels = PRESETS[preset()];
  const fetchers = {};
  const fetcherOf = (src) => (fetchers[src.id] ||= new TileFetcher(src, { signal: ac.signal }));
  const make = async (src) => renderPack({ bbox, levels, name: $('name').value.trim() || 'My map',
    lang: $('lang').value, source: src, schema: await schemaOf(src), maplibregl, fetcher: fetcherOf(src), signal: ac.signal,
    onProgress: (p) => {
      $('fill').style.width = `${(100 * p.done / p.total).toFixed(1)}%`;
      $('ptext').textContent = `${p.done.toLocaleString('en')} of ${p.total.toLocaleString('en')} tiles` +
        (p.eta !== null && p.done < p.total ? `, about ${timeText(p.eta)} left` : '') +
        ` · map tiles from ${src.title}: fetched ${p.vectorTiles.toLocaleString('en')}, from cache ${p.fromCache.toLocaleString('en')}`;
    } });
  try {
    $('ptext').textContent = 'Checking the area…';
    // the sampled tiles go through the pack's own fetcher: cached, and counted in its 50 MB
    const pick = await chooseSource({ bbox, levels, search: location.search, size: async (src, z, x, y) => {
      const f = fetcherOf(src);
      await f.resolve();
      const b = await f.get(z, x, y);
      return b ? b.length : 0;
    } });
    if (ac.signal.aborted) throw new DOMException('The run was cancelled.', 'AbortError');
    const WHY = { dense: ' (the area is too dense for OpenFreeMap)', 'too-large': ' (too large for OpenFreeMap)', unreachable: ' (OpenFreeMap did not answer)' };
    let used = pick.source, why = WHY[pick.reason] || '', out;
    try {
      out = await make(used);
    } catch (e) {
      // OpenFreeMap's limits ran out, or a tile server failed mid-pack: start again from the other source
      const other = fallbackSource({ used, code: e.code, fitsOfm: fitsOpenFreeMap(bbox, levels), forced });
      if (!other) throw e;
      why = e.code === 'source' ? ` (${used.title} failed: ${e.message})` : ' (the area was bigger than it looked for OpenFreeMap’s limits)';
      $('ptext').textContent = `${used.title} failed; starting again from ${other.title}…`;
      try {
        out = await make(other);
      } catch (e2) {
        if (e2.name === 'AbortError') throw e2;
        throw new Error(`Both map sources failed. ${used.title}: ${e.message} ${other.title}: ${e2.message}`);
      }
      used = other;
    }
    const { bytes, stats } = out;
    showPack(bytes);
    message($('result'), `Done: ${bytesText(bytes.length)}, ${stats.tiles.toLocaleString('en')} tiles (${stats.empty.toLocaleString('en')} empty), ` +
      `${stats.names.toLocaleString('en')} names for search. Map data from ${esc(used.title)}${used.id === 'openfreemap' ? ', with peaks' : ''}${esc(why)}.`, 'ok');
  } catch (e) {
    if (e.name === 'AbortError') message($('result'), 'Cancelled. Press Make again to continue: what was fetched is kept in this browser.');
    else message($('result'), esc(e.message || e), 'err');
  } finally {
    run = null;
    $('cancel').hidden = true;
    $('make').disabled = !bbox;
  }
});
$('cancel').addEventListener('click', () => run?.abort());

// copy a file into AppFiles/offlinemap/ on the reader's card
async function toCard(name, bytes) {
  if (!card.handle) await card.connect();
  const files = await card.handle.getDirectoryHandle('AppFiles', { create: true });
  const dir = await files.getDirectoryHandle(APP, { create: true });
  const fh = await dir.getFileHandle(name, { create: true });
  const w = await fh.createWritable();
  await w.write(bytes);
  await w.close();
}
$('download').addEventListener('click', () => packed && download(safeName($('name').value, '.map'), packed));
$('write').hidden = !canCopy;
$('write').addEventListener('click', async () => {
  if (!packed) return;
  const name = safeName($('name').value, '.map');
  try {
    await toCard(name, packed);
    message($('saved'), `Written to AppFiles/${APP}/${esc(name)}. Eject the card, then open Offline Map.`, 'ok');
  } catch (e) { message($('saved'), esc(e.message), 'err'); }
});
$('rdownload').addEventListener('click', () => routeGpx && download(safeName($('rname').value, '.gpx'), new TextEncoder().encode(routeGpx), 'application/gpx+xml'));
$('rwrite').hidden = !canCopy;
$('rwrite').addEventListener('click', async () => {
  if (!routeGpx) return;
  const name = safeName($('rname').value, '.gpx');
  try {
    await toCard(name, new TextEncoder().encode(routeGpx));
    message($('rsaved'), `Written to AppFiles/${APP}/${esc(name)}. In Offline Map: Menu, Routes.`, 'ok');
  } catch (e) { message($('rsaved'), esc(e.message), 'err'); }
});
card.restore().catch(() => {});
