// Routes in the map maker: a route drawn by clicking (or loaded from a GPX), its length and area, the
// names of the streets it follows (from the vector tiles' street label lines), and the GPX written next
// to the pack. Points are [lon, lat].

const R = 6371008.8;
const RAD = Math.PI / 180;

export function lengthM(points) {
  let m = 0;
  for (let i = 1; i < points.length; i++) {
    const [a, b] = [points[i - 1], points[i]];
    const p1 = a[1] * RAD, p2 = b[1] * RAD, dp = p2 - p1, dl = (b[0] - a[0]) * RAD;
    const h = Math.sin(dp / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) ** 2;
    m += 2 * 6371000 * Math.asin(Math.min(1, Math.sqrt(h)));
  }
  return m;
}

// [w, s, e, n] around the points, with a margin in metres
export function bboxWithMargin(points, m) {
  let w = Infinity, s = Infinity, e = -Infinity, n = -Infinity;
  for (const [x, y] of points) { w = Math.min(w, x); e = Math.max(e, x); s = Math.min(s, y); n = Math.max(n, y); }
  const dLat = m / 111195, dLon = m / (111195 * Math.cos(((s + n) / 2) * RAD));
  return [w - dLon, s - dLat, e + dLon, n + dLat];
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const unesc = (s) => String(s).replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
const f7 = (v) => v.toFixed(7);

// the GPX: metadata name first (the app takes the first <name>), street labels as waypoints, the track
export function toGpx({ name, points, labels = [] }) {
  return '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<gpx version="1.1" creator="Touch Licorice offline map maker" xmlns="http://www.topografix.com/GPX/1/1">\n' +
    `<metadata><name>${esc(name)}</name></metadata>\n` +
    labels.map((l) => `<wpt lat="${f7(l.lat)}" lon="${f7(l.lon)}"><name>${esc(l.name)}</name><type>street</type></wpt>\n`).join('') +
    `<trk><name>${esc(name)}</name><trkseg>\n` +
    points.map(([x, y]) => `<trkpt lat="${f7(y)}" lon="${f7(x)}"/>\n`).join('') +
    '</trkseg></trk>\n</gpx>\n';
}

export function parseGpx(text) {
  const points = [];
  for (const m of String(text).matchAll(/<\s*(?:\w+:)?(?:trkpt|rtept)\b([^>]*)>/g)) {
    const lat = /lat\s*=\s*["']([^"']+)["']/.exec(m[1]), lon = /lon\s*=\s*["']([^"']+)["']/.exec(m[1]);
    if (lat && lon && isFinite(+lat[1]) && isFinite(+lon[1])) points.push([+lon[1], +lat[1]]);
  }
  const nm = /<(?:trk|rte)\b[^>]*>\s*<name>([^<]*)<\/name>/.exec(text) || /<name>([^<]*)<\/name>/.exec(text);
  return { name: nm ? unesc(nm[1]).trim() : '', points };
}

// local metres around a point: [x, y] = east, north
function local(lat0) {
  const k = Math.cos(lat0 * RAD);
  return ([lon, lat]) => [lon * RAD * R * k, lat * RAD * R];
}
function nearest(p, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1], L = dx * dx + dy * dy || 1;
  const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L));
  const q = [a[0] + t * dx, a[1] + t * dy];
  return { d: Math.hypot(p[0] - q[0], p[1] - q[1]), t, q };
}
const angle = (a, b) => Math.atan2(b[1] - a[1], b[0] - a[0]);
function undirectedDiff(a, b) {
  let d = Math.abs(a - b) % Math.PI;
  return Math.min(d, Math.PI - d);
}

// the streets a route follows: label line pieces within maxM metres of a route segment and within maxDeg
// of its direction; one label per street per 300 m of the route, at the middle of that stretch
export function streetLabels(routePoints, features, maxM = 12, maxDeg = 25) {
  if (routePoints.length < 2) return [];
  const lat0 = routePoints.reduce((s, p) => s + p[1], 0) / routePoints.length;
  const P = local(lat0);
  const rp = routePoints.map(P);
  const along = [0];
  for (let i = 1; i < rp.length; i++) along.push(along[i - 1] + Math.hypot(rp[i][0] - rp[i - 1][0], rp[i][1] - rp[i - 1][1]));
  const hits = new Map();                         // name -> [{s (metres along the route), q (local point)}]
  for (const f of features) {
    const name = f.properties && f.properties.name;
    if (!name || !f.geometry) continue;
    const parts = f.geometry.type === 'LineString' ? [f.geometry.coordinates] : f.geometry.type === 'MultiLineString' ? f.geometry.coordinates : [];
    for (const part of parts) {
      const lp = part.map(P);
      for (let j = 1; j < lp.length; j++) {
        const mid = [(lp[j - 1][0] + lp[j][0]) / 2, (lp[j - 1][1] + lp[j][1]) / 2];
        const la = angle(lp[j - 1], lp[j]);
        for (let i = 1; i < rp.length; i++) {
          const n = nearest(mid, rp[i - 1], rp[i]);
          if (n.d <= maxM && undirectedDiff(la, angle(rp[i - 1], rp[i])) <= maxDeg * RAD) {
            const s = along[i - 1] + n.t * (along[i] - along[i - 1]);
            if (!hits.has(name)) hits.set(name, []);
            hits.get(name).push({ s, q: n.q });
          }
        }
      }
    }
  }
  const out = [];
  const back = ([x, y]) => [x / (R * Math.cos(lat0 * RAD)) / RAD, y / R / RAD];
  for (const [name, list] of hits) {
    list.sort((a, b) => a.s - b.s);
    let run = [list[0]];
    const flush = () => {
      const mid = run[Math.floor(run.length / 2)];
      const [lon, lat] = back(mid.q);
      out.push({ name, lon, lat });
    };
    for (let k = 1; k < list.length; k++) {
      if (list[k].s - run[0].s > 300) { flush(); run = [list[k]]; } else run.push(list[k]);
    }
    flush();
  }
  return out;
}
