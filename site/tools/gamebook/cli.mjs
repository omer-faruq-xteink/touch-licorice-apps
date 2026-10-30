// node site/tools/gamebook/cli.mjs STORY_FILE [OUT.story]: convert on the command line
// (Twine .html, Twee, Ink .ink, a .story to check, a Project Aon .epub, a zip of Twee files)
import { readFileSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
import { convertFile } from './convert.js';

const [, , input, output] = process.argv;
const r = await convertFile(basename(input), new Uint8Array(readFileSync(input)));
for (const w of r.warnings) console.error('warning: ' + w);
if (output) writeFileSync(output, r.story);
else process.stdout.write(r.story);
console.error(`${r.info.format}: ${r.info.passages} passages`);
