// Piano Follow converter: MusicXML / MXL / ABC -> engraved 1-bit pages + note map -> one .xtscore file.
// Shared by the converter page (browser) and the catalog tool (Node); the caller passes in a Verovio
// toolkit, a rasterizer and zlib functions, so this module has no platform code.
//
// .xtscore: "XTSCORE1", uint32 LE header length N, N bytes of JSON header, then zlib streams.
// No title on the page (the app's status bar shows it).
// Header: { v, title, composer, arranger, license, source, url, level, w, h,
//           pages: [[offset, length], ...], map: [offset, length] }   (offsets from the file start)
// Page: 440 rows of 100 bytes (800 x 440), high bit first, 1 = black.
// Map: { bars: [[page, x, y, w]], onsets: [[t, bar, page, x, y, [rh], [lh]]], turn: [[sys, bar]] }
//   t in quarter notes (performance order: repeats unfolded), bar 1-based into bars, x/y in pixels of
//   the page (first notehead of the onset; bars: left edge, bottom of the lowest staff, width),
//   pitches as MIDI numbers, turn[i] = 1-based onset index of the first onset in page i's last
//   system and in its last bar.

// the page: the reader in landscape (800 x 480) under the app's 40 px status bar
export const W = 800, H = 440, ROW = W / 8, MAGIC = 'XTSCORE1';
export const SCALE = 55;                 // Verovio scale (%): sets the size of the music on the page
export const LANDSCAPE = { w: W, h: H, scale: SCALE };
const layoutOf = (l) => (typeof l === 'number' ? { ...LANDSCAPE, scale: l } : { ...LANDSCAPE, ...(l || {}) });
export function verovioOptions(layout = LANDSCAPE) {
  const { w, h, scale } = layoutOf(layout);
  return {
    pageWidth: Math.round(w * 100 / scale), pageHeight: Math.round(h * 100 / scale), scale,
    // tight vertical spacing: a landscape page holds two systems only just, and a slightly taller one
    // (a second voice) would otherwise be left alone on its page
    pageMarginLeft: 30, pageMarginRight: 30, pageMarginTop: 10, pageMarginBottom: 4, spacingSystem: 1, spacingStaff: 8,
    breaksNoWidow: true,
    breaks: 'auto', header: 'none', footer: 'none', adjustPageHeight: false,   // the app shows the title
    // thin lines vanish in 1 bit at this size: as thick as Verovio allows
    staffLineWidth: 0.3, stemWidth: 0.4, ledgerLineThickness: 0.4, barLineWidth: 0.5,
    svgViewBox: false, svgHtml5: false, removeIds: false,
  };
}

// --- input -----------------------------------------------------------------------------------
function load(tk, input) {
  const name = input.name.toLowerCase();
  if (name.endsWith('.mxl')) {
    const buf = input.data instanceof Uint8Array ? input.data : new TextEncoder().encode(input.data);
    if (!tk.loadZipDataBuffer(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength))) throw new Error('Could not read this MXL file');
  } else {
    const text = typeof input.data === 'string' ? input.data : new TextDecoder().decode(input.data);
    if (!tk.loadData(text)) throw new Error('Could not read this file');
  }
  // through MEI once more without what costs room on a small page: instrument names in front of
  // every system ("Pno.") and tempo marks (their metronome glyphs do not draw in 1 bit either)
  const mei = tk.getMEI();
  // attributes lazily ([^>]*? stops before "/>"), so a self-closing tag is not read as an opening one
  // whose body would run on to the next closing tag of that name, music and all
  const tag = (t) => new RegExp(`<${t}(?:\\s[^>]*?)?(?:/>|>[\\s\\S]*?</${t}>)`, 'g');
  // and chord symbols (guitar chords on a piano score; their sharp glyphs do not draw either)
  const lean = mei.replace(tag('label'), '').replace(tag('labelAbbr'), '').replace(tag('tempo'), '').replace(tag('harm'), '');
  if (lean !== mei && !tk.loadData(lean)) throw new Error('Could not read this file');
}

// --- SVG walking ---------------------------------------------------------------------------------
// The few things we need from Verovio's SVG: per note id its notehead position and staff number,
// per measure its staff-line box, and the systems in order. Coordinates are in viewBox units.
function walk(svg, w) {
  const vb = /class="definition-scale"[^>]*viewBox="0 0 ([\d.]+) ([\d.]+)"/.exec(svg);
  const pm = /class="page-margin" transform="translate\(([-\d.]+),\s*([-\d.]+)\)"/.exec(svg);
  const k = w / Number(vb[1]), ox = Number(pm[1]), oy = Number(pm[2]);
  const px = (x, y) => [(x + ox) * k, (y + oy) * k];
  const notes = new Map(), measures = [], systems = [];
  const stack = [];
  let system = null, measure = null, staffN = 0, staff = null;
  const re = /<(\/?)([a-zA-Z]+)([^>]*?)(\/?)>/g;
  let m;
  while ((m = re.exec(svg))) {
    const [, close, tag, attrs, self] = m;
    if (close) {
      const top = stack.pop();
      if (top === 'system') system = null;
      else if (top === 'measure') measure = null;
      else if (top === 'staff') staff = null;
      continue;
    }
    const cls = /class="([^"]*)"/.exec(attrs)?.[1] || '';
    const id = /id="([^"]*)"/.exec(attrs)?.[1];
    let kind = '';
    if (tag === 'g') {
      const c = cls.split(' ')[0];
      if (c === 'system') { system = { id, measures: [] }; systems.push(system); kind = 'system'; }
      else if (c === 'measure' && system) { measure = { id, system, x0: Infinity, x1: -Infinity, y1: -Infinity }; system.measures.push(measure); measures.push(measure); staffN = 0; kind = 'measure'; }
      else if (c === 'staff' && measure) { staffN += 1; staff = staffN; kind = 'staff'; }
      else if (c === 'note' && id) { notes.set(id, { staff, measure, x: null, y: null }); kind = 'note:' + id; }
    } else if (tag === 'use') {
      const t = /translate\(([-\d.]+),\s*([-\d.]+)\)/.exec(attrs);
      const owner = [...stack].reverse().find(s => s.startsWith('note:'));
      if (t && owner) {
        const n = notes.get(owner.slice(5));
        if (n.x === null) { const [x, y] = px(Number(t[1]), Number(t[2])); n.x = x; n.y = y; }
      }
    } else if (tag === 'path' && staff && measure && stack[stack.length - 1] === 'staff') {
      const d = /d="M([-\d.]+) ([-\d.]+) L([-\d.]+) ([-\d.]+)"/.exec(attrs);
      if (d && d[2] === d[4]) {                           // a staff line
        const [a, y] = px(Number(d[1]), Number(d[2])), [b] = px(Number(d[3]), Number(d[4]));
        measure.x0 = Math.min(measure.x0, a, b); measure.x1 = Math.max(measure.x1, a, b); measure.y1 = Math.max(measure.y1, y);
      }
    }
    if (!self && tag !== 'path' && tag !== 'use') stack.push(kind || tag);
    else if (!self && (tag === 'path' || tag === 'use')) stack.push(tag);
  }
  return { notes, measures, systems };
}

// --- raster ----------------------------------------------------------------------------------------
export function to1bit(rgba, w = W, h = H) {
  const out = new Uint8Array((w / 8) * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4, a = rgba[i + 3] / 255;
      const lum = (0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2]) * a + 255 * (1 - a);
      if (lum < 200) out[y * (w / 8) + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return out;
}

// --- convert -----------------------------------------------------------------------------------------
export async function convert(tk, raster, input, meta = {}, layout = LANDSCAPE) {
  const { w: PW, h: PH } = layoutOf(layout);
  tk.setOptions(verovioOptions(layout));
  load(tk, input);
  const count = tk.getPageCount();
  if (!count) throw new Error('No music found in this file');
  const pages = [], noteAt = new Map(), barOf = new Map(), bars = [], lastSys = [], lastBar = [];
  for (let p = 1; p <= count; p++) {
    const svg = tk.renderToSVG(p);
    pages.push(to1bit(await raster(svg, PW, PH), PW, PH));
    const { notes, measures, systems } = walk(svg, PW);
    for (const [id, n] of notes) noteAt.set(id, { ...n, page: p });
    for (const ms of measures) {
      if (!barOf.has(ms.id)) {
        bars.push([p, Math.round(ms.x0), Math.round(ms.y1), Math.round(ms.x1 - ms.x0)]);
        barOf.set(ms.id, bars.length);
      }
    }
    const sys = systems[systems.length - 1];
    lastSys.push(new Set(sys ? sys.measures.map(x => x.id) : []));
    lastBar.push(sys && sys.measures.length ? sys.measures[sys.measures.length - 1].id : null);
  }
  // onsets from the timemap (repeats come unfolded)
  const tm = tk.renderToTimemap({ includeMeasures: true, includeRests: false });
  const base = id => id.replace(/-rend\d+$/, '');       // repeats come as copies: "<id>-rend2"
  const onsets = [], onsetMeasure = [];
  let measureId = null;
  for (const e of tm) {
    if (e.measureOn) measureId = base(e.measureOn);
    if (!e.on || !e.on.length) continue;
    const rh = new Set(), lh = new Set();
    let first = null;
    for (const id of e.on) {
      const n = noteAt.get(base(id));
      if (!n || n.x === null) continue;
      const pitch = tk.getMIDIValuesForElement(base(id))?.pitch;
      if (typeof pitch !== 'number' || pitch < 0) continue;
      (n.staff === 2 ? lh : rh).add(pitch);
      if (!first || n.y < first.y && n.staff !== 2 && first.staff === 2) first = n;
    }
    if (!first) continue;
    const mid = measureId && barOf.has(measureId) ? measureId : first.measure.id;
    const sort = s => [...s].sort((a, b) => a - b);
    onsets.push([e.qstamp, barOf.get(mid), first.page, Math.round(first.x), Math.round(first.y), sort(rh), sort(lh)]);
    onsetMeasure.push(mid);
  }
  const turn = [];
  for (let p = 1; p <= count; p++) {
    const onPage = i => onsets[i][2] === p;
    let s = onsets.findIndex((o, i) => onPage(i) && lastSys[p - 1].has(onsetMeasure[i]));
    let b = onsets.findIndex((o, i) => onPage(i) && onsetMeasure[i] === lastBar[p - 1]);
    if (s < 0) s = onsets.findLastIndex((o, i) => onPage(i));
    if (b < 0) b = s;
    turn.push([s + 1, Math.max(b, s) + 1]);
  }
  const header = {
    v: 1, title: meta.title || input.name.replace(/\.[^.]+$/, ''), composer: meta.composer || '', arranger: meta.arranger || '',
    license: meta.license || '', source: meta.source || '', url: meta.url || '', level: meta.level || '', w: PW, h: PH,
  };
  return { header, pages, map: { bars, onsets, turn } };
}

// --- file -------------------------------------------------------------------------------------------
export async function pack(result, deflate) {
  const enc = new TextEncoder();
  const blobs = [];
  for (const p of result.pages) blobs.push(await deflate(p));
  const mapBlob = await deflate(enc.encode(JSON.stringify(result.map)));
  let n = 0, headerBytes;
  for (;;) {                                   // offsets depend on the header's own length
    let off = 12 + n;
    const pages = blobs.map(b => { const e = [off, b.length]; off += b.length; return e; });
    const header = { ...result.header, pages, map: [off, mapBlob.length] };
    headerBytes = enc.encode(JSON.stringify(header));
    if (headerBytes.length === n) break;
    n = headerBytes.length;
  }
  const total = 12 + n + blobs.reduce((a, b) => a + b.length, 0) + mapBlob.length;
  const out = new Uint8Array(total);
  out.set(enc.encode(MAGIC), 0);
  new DataView(out.buffer).setUint32(8, n, true);
  out.set(headerBytes, 12);
  let off = 12 + n;
  for (const b of [...blobs, mapBlob]) { out.set(b, off); off += b.length; }
  return out;
}

export async function unpack(bytes, inflate) {
  const dec = new TextDecoder();
  if (bytes.length < 12 || dec.decode(bytes.slice(0, 8)) !== MAGIC) throw new Error('Not a Piano Follow file');
  const n = new DataView(bytes.buffer, bytes.byteOffset).getUint32(8, true);
  const header = JSON.parse(dec.decode(bytes.slice(12, 12 + n)));
  const pages = [];
  for (const [o, l] of header.pages) pages.push(await inflate(bytes.slice(o, o + l)));
  const [mo, ml] = header.map;
  const map = JSON.parse(dec.decode(await inflate(bytes.slice(mo, mo + ml))));
  return { header, pages, map };
}
