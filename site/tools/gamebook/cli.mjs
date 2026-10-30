// node site/tools/gamebook/cli.mjs STORY_FILE [OUT.story]: convert on the command line
import { readFileSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
import { convert } from './convert.js';

const [, , input, output] = process.argv;
const r = convert(basename(input), readFileSync(input, 'utf8'));
for (const w of r.warnings) console.error('warning: ' + w);
if (output) writeFileSync(output, r.story);
else process.stdout.write(r.story);
console.error(`${r.info.format}: ${r.info.passages} passages`);
