// Node side of the converter: Verovio toolkit, resvg rasterizer, zlib.
import createVerovioModule from 'verovio/wasm';
import { VerovioToolkit } from 'verovio/esm';
import { Resvg } from '@resvg/resvg-js';
import zlib from 'node:zlib';

export async function nodeToolkit() {
  const M = await createVerovioModule();
  return new VerovioToolkit(M);
}

export async function nodeRaster(svg, w, h) {
  const r = new Resvg(svg, { background: 'white', fitTo: { mode: 'width', value: w }, font: { loadSystemFonts: true } });
  const img = r.render();
  const out = new Uint8Array(w * h * 4).fill(255);
  const src = img.pixels, iw = img.width, ih = Math.min(img.height, h);
  for (let y = 0; y < ih; y++) out.set(src.subarray(y * iw * 4, y * iw * 4 + Math.min(iw, w) * 4), y * w * 4);
  return out;
}

export async function nodeDeflate(bytes) { return new Uint8Array(zlib.deflateSync(bytes, { level: 9 })); }
export async function nodeInflate(bytes) { return new Uint8Array(zlib.inflateSync(bytes)); }
