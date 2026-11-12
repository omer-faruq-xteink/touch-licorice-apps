// node level_cli.mjs FILE.(musicxml|xml|mxl|abc) [BPM]: prints the estimated level (used by pdmx_select.py)
import fs from 'node:fs';
import path from 'node:path';
import { convert } from '../../site/tools/piano/convert.mjs';
import { nodeToolkit } from './node_raster.mjs';
import { level } from './level.mjs';

const [file, bpm] = process.argv.slice(2);
const tk = await nodeToolkit();
const data = file.toLowerCase().endsWith('.mxl') ? new Uint8Array(fs.readFileSync(file)) : fs.readFileSync(file, 'utf8');
const blank = async (svg, w, h) => new Uint8Array(w * h * 4).fill(255);     // no pages needed here
const r = await convert(tk, blank, { name: path.basename(file), data });
console.log(level(r.map, bpm ? Number(bpm) : undefined));
