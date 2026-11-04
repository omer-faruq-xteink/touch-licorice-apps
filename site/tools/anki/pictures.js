// Right-to-left text (Arabic, Hebrew, Persian, Urdu ...) as pictures for the Anki app. The reader
// lays text out left to right only and refuses a string with a right-to-left letter, so the
// converter draws each such paragraph here, in the browser (which joins Arabic letters and places
// the vowel marks), and the card keeps a 1-bit PNG of each drawn line instead.
//
//   const draw = await makePicturer()          loads the fonts once
//   await draw(text, big) -> null | { text, pics }
//
// text: the side with every right-to-left paragraph replaced by one line per drawn line,
// "\x01k,h,w,a" (the k-th picture, its height and width, a = r / l: right or left aligned); pics:
// the PNGs in base64, comma separated. One picture per line, drawn whole: the reader refuses
// g:image's src on a decoded picture (found on the device), so lines cannot share one sheet.
// null: nothing right-to-left on this side. Browser only (canvas, fonts).

import { crc32 } from '../../assets/zip.js';

export const RTL = /[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/u;
const STRONG = /[\p{L}]/u;
const WIDTH = 440;          // the app's card width (480 - 2 x 20)
const MAX_LINES = 16;       // drawn lines per side, at most
const FAMILY = '"Noto Naskh Arabic", "Noto Sans Hebrew", "Segoe UI", Arial, sans-serif';
const FONTS = 'https://fonts.googleapis.com/css2?family=Noto+Naskh+Arabic:wght@400..700&family=Noto+Sans+Hebrew:wght@400..700&display=block';

export const hasRtl = (s) => RTL.test(s);

// ------------------------------------------------------------------ PNG, 1 bit gray

function chunk(type, data) {
  const out = new Uint8Array(12 + data.length);
  const v = new DataView(out.buffer);
  v.setUint32(0, data.length);
  for (let i = 0; i < 4; i++) out[4 + i] = type.charCodeAt(i);
  out.set(data, 8);
  v.setUint32(8 + data.length, crc32(out.subarray(4, 8 + data.length)));
  return out;
}

async function zlib(bytes) {
  const r = new Response(new Blob([bytes]).stream().pipeThrough(new CompressionStream('deflate')));
  return new Uint8Array(await r.arrayBuffer());
}

// ink: Uint8Array(w * h), 1 = black
async function png1(ink, w, h) {
  const stride = (w + 7) >> 3;
  const raw = new Uint8Array((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    const row = y * (stride + 1);
    for (let x = 0; x < w; x++) if (!ink[y * w + x]) raw[row + 1 + (x >> 3)] |= 0x80 >> (x & 7);   // 1 = white
  }
  const ihdr = new Uint8Array(13);
  const v = new DataView(ihdr.buffer);
  v.setUint32(0, w); v.setUint32(4, h);
  ihdr[8] = 1; ihdr[9] = 0;                                  // bit depth 1, gray
  const parts = [new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', await zlib(raw)), chunk('IEND', new Uint8Array(0))];
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

function base64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

// ------------------------------------------------------------------ drawing

export async function makePicturer() {
  if (!document.querySelector(`link[href="${FONTS}"]`)) {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = FONTS;
    const loaded = new Promise((r) => { link.onload = r; link.onerror = r; });
    document.head.append(link);
    await loaded;
  }
  await Promise.all([
    document.fonts.load(`600 40px "Noto Naskh Arabic"`, '\u0645\u0650\u0646\u0652'),
    document.fonts.load(`600 40px "Noto Sans Hebrew"`, '\u05E9\u05DC\u05D5\u05DD'),
  ]).catch(() => {});
  const cv = document.createElement('canvas');
  const g = cv.getContext('2d', { willReadFrequently: true });

  // one line of text drawn and cut to its ink: { ink, w }
  function drawLine(text, px, lh, rtl) {
    const cw = WIDTH + 2 * px;
    if (cv.width !== cw || cv.height !== lh) { cv.width = cw; cv.height = lh; }
    g.fillStyle = '#fff';
    g.fillRect(0, 0, cw, lh);
    g.fillStyle = '#000';
    g.font = `600 ${px}px ${FAMILY}`;
    g.direction = rtl ? 'rtl' : 'ltr';
    g.textAlign = 'left';
    g.textBaseline = 'alphabetic';
    g.fillText(text, px, Math.round(lh * 0.66));
    const d = g.getImageData(0, 0, cw, lh).data;
    let x0 = cw, x1 = -1;
    const all = new Uint8Array(cw * lh);
    for (let y = 0; y < lh; y++) {
      for (let x = 0; x < cw; x++) {
        if (d[(y * cw + x) * 4] < 150) { all[y * cw + x] = 1; if (x < x0) x0 = x; if (x > x1) x1 = x; }
      }
    }
    if (x1 < 0) return { ink: new Uint8Array(lh), w: 1 };
    const w = Math.min(x1 - x0 + 1, WIDTH);
    const ink = new Uint8Array(w * lh);
    for (let y = 0; y < lh; y++) for (let x = 0; x < w; x++) ink[y * w + x] = all[y * cw + x0 + x];
    return { ink, w };
  }

  function wrap(para, px) {
    g.font = `600 ${px}px ${FAMILY}`;
    const out = [];
    let line = '';
    for (const word of para.split(/ +/)) {
      if (!word) continue;
      const cand = line ? line + ' ' + word : word;
      if (line && g.measureText(cand).width > WIDTH) { out.push(line); line = word; } else line = cand;
    }
    if (line) out.push(line);
    return out;
  }

  return async function draw(text, big) {
    const paras = text.split('\n');
    if (!paras.some(hasRtl)) return null;
    const px = big ? 56 : 32, lh = Math.ceil(px * 1.75);
    const pics = [], out = [];
    for (const para of paras) {
      if (!hasRtl(para)) { out.push(para); continue; }
      const first = para.match(STRONG);
      const rtl = !first || hasRtl(first[0]);
      for (const l of wrap(para, px)) {
        if (pics.length >= MAX_LINES) { out.push('…'); break; }
        const { ink, w } = drawLine(l, px, lh, rtl);
        pics.push(base64(await png1(ink, w, lh)));
        out.push(`\x01${pics.length},${lh},${w},${rtl ? 'r' : 'l'}`);
      }
    }
    if (!pics.length) return null;
    return { text: out.join('\n'), pics: pics.join(',') };
  };
}
