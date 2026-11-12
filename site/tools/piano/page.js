// The converter page: a MusicXML / MXL / ABC file -> .xtscore for Piano Follow, in this browser.
// Verovio comes from a public CDN (the same version as tools/piano/package.json).
import { chrome, dropZone, download, message, bytesText, esc } from '../../assets/site.js';
import { canCopy, card } from '../../assets/store.js';
import { convert, pack, unpack, W, H } from './convert.mjs';

const VEROVIO = 'https://cdn.jsdelivr.net/npm/verovio@6.4.1/dist/';
const APP = 'pianofollow';
const $ = (id) => document.getElementById(id);
chrome('piano');

let toolkit = null, file = null, packed = null;

async function getToolkit() {
  if (!toolkit) {
    const [{ default: createModule }, { VerovioToolkit }] = await Promise.all([import(VEROVIO + 'verovio-module.mjs'), import(VEROVIO + 'verovio.mjs')]);
    toolkit = new VerovioToolkit(await createModule());
  }
  return toolkit;
}

// SVG -> RGBA through an image on a white canvas
async function raster(svg, w, h) {
  const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
  try {
    const img = new Image();
    await new Promise((ok, fail) => { img.onload = ok; img.onerror = () => fail(new Error('could not draw a page')); img.src = url; });
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    const g = c.getContext('2d', { willReadFrequently: true });
    g.fillStyle = '#fff'; g.fillRect(0, 0, w, h);
    g.drawImage(img, 0, 0, w, h);
    return g.getImageData(0, 0, w, h).data;
  } finally { URL.revokeObjectURL(url); }
}

const stream = (kind) => async (bytes) =>
  new Uint8Array(await new Response(new Blob([bytes]).stream().pipeThrough(new kind('deflate'))).arrayBuffer());
const deflate = stream(CompressionStream), inflate = stream(DecompressionStream);

function preview(pages) {
  $('pages').innerHTML = '';
  for (const p of pages) {
    const c = document.createElement('canvas');
    c.width = W; c.height = H; c.className = 'page';
    const g = c.getContext('2d'), img = g.createImageData(W, H);
    for (let i = 0; i < W * H; i++) {
      const v = p[(i / W | 0) * (W / 8) + ((i % W) >> 3)] & (0x80 >> (i % W & 7)) ? 0 : 255;
      img.data.set([v, v, v, 255], i * 4);
    }
    g.putImageData(img, 0, 0);
    $('pages').appendChild(c);
  }
}

const safeName = (s) => (s.normalize('NFKD').replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '-').slice(0, 60) || 'piece') + '.xtscore';

dropZone($('drop'), async (files) => {
  file = files[0];
  packed = null;
  $('step2').hidden = false;
  $('title').value = file.name.replace(/\.[^.]+$/, '');
  message($('result'), '');
  $('pages').innerHTML = '';
});

$('go').addEventListener('click', async () => {
  if (!file) return;
  $('go').disabled = true;
  message($('result'), 'Loading the engraver …');
  try {
    const tk = await getToolkit();
    message($('result'), 'Engraving …');
    const data = file.name.toLowerCase().endsWith('.mxl') ? file.bytes : new TextDecoder().decode(file.bytes);   // dropZone gives {name, bytes}
    const r = await convert(tk, raster, { name: file.name, data }, { title: $('title').value.trim(), composer: $('composer').value.trim(), source: 'converted by the user' });
    if (!r.map.onsets.length) throw new Error('No notes found in this file');
    packed = await pack(r, deflate);
    const back = await unpack(packed, inflate);              // the file reads back as the app will see it
    preview(back.pages);
    message($('result'), `${back.pages.length} page${back.pages.length > 1 ? 's' : ''}, ${r.map.onsets.length} notes and chords, ${bytesText(packed.length)}.`, 'ok');
    $('save').hidden = false;
  } catch (e) {
    message($('result'), e.message, 'err');
  }
  $('go').disabled = false;
});

$('download').addEventListener('click', () => packed && download(safeName($('title').value), packed));

$('write').hidden = !canCopy;
$('write').addEventListener('click', async () => {
  if (!packed) return;
  try {
    if (!card.handle) await card.connect();
    const files = await card.handle.getDirectoryHandle('AppFiles', { create: true });
    const dir = await files.getDirectoryHandle(APP, { create: true });
    const name = safeName($('title').value);
    const fh = await dir.getFileHandle(name, { create: true });
    const w = await fh.createWritable();
    await w.write(packed);
    await w.close();
    message($('saved'), `Written to AppFiles/${APP}/${esc(name)}. Eject the card, then open Piano Follow: it is under My pieces.`, 'ok');
  } catch (e) {
    message($('saved'), e.message, 'err');
  }
});
card.restore().catch(() => {});
