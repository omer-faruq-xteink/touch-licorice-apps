// node make_fixture.mjs IN OUT.xtscore [--png DIR] [--scale N] [--title T]: converts one file (used by the Lua tests
// and for looking at the pages: --png writes each page as a 1-bit PNG).
import fs from 'node:fs';
import path from 'node:path';
import { convert, pack } from '../../../site/tools/piano/convert.mjs';
import { nodeToolkit, nodeRaster, nodeDeflate } from '../node_raster.mjs';
import { Resvg } from '@resvg/resvg-js';

const [inp, out, ...rest] = process.argv.slice(2);
const opt = k => { const i = rest.indexOf(k); return i >= 0 ? rest[i + 1] : null; };
const tk = await nodeToolkit();
const isText = !inp.toLowerCase().endsWith('.mxl');
const data = isText ? fs.readFileSync(inp, 'utf8') : new Uint8Array(fs.readFileSync(inp));
const r = await convert(tk, nodeRaster, { name: path.basename(inp), data }, { title: opt('--title') || path.basename(inp).replace(/\.[^.]+$/, '') }, opt('--scale') ? Number(opt('--scale')) : undefined);
fs.writeFileSync(out, await pack(r, nodeDeflate));
const png = opt('--png');
if (png) {
  fs.mkdirSync(png, { recursive: true });
  const W = r.header.w, H = r.header.h;
  r.pages.forEach((p, i) => {
    let rects = '';
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (p[y * W / 8 + (x >> 3)] & (0x80 >> (x & 7))) rects += `M${x} ${y}h1v1h-1z`;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><rect width="${W}" height="${H}" fill="white"/><path d="${rects}" fill="black"/></svg>`;
    fs.writeFileSync(path.join(png, `${path.basename(out, '.xtscore')}-${i + 1}.png`), new Resvg(svg).render().asPng());
  });
}
console.log(`${out}: ${r.pages.length} pages, ${r.map.onsets.length} onsets, ${fs.statSync(out).size} bytes`);
