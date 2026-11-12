// Difficulty estimate (tools/piano/level.mjs)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { convert } from '../../../site/tools/piano/convert.mjs';
import { nodeToolkit, nodeRaster } from '../node_raster.mjs';
import { level, features } from '../level.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const tk = await nodeToolkit();
const mapOf = async name => (await convert(tk, nodeRaster, { name, data: fs.readFileSync(path.join(HERE, 'fixtures', name), 'utf8') })).map;

test('features of the scale', async () => {
  const f = features(await mapOf('scale.musicxml'));
  assert.equal(f.span, 24);                       // C3..C5
  assert.equal(f.onsets, 16);
  assert.ok(f.lhActive > 0 && f.lhActive < 0.5);  // LH only on the first beat of each bar
});
test('scale is beginner, dense is advanced', async () => {
  assert.equal(level(await mapOf('scale.musicxml')), 'beginner');
  assert.equal(level(await mapOf('dense.musicxml')), 'advanced');
});
test('level CLI prints a level', () => {
  const out = execFileSync(process.execPath, [path.join(HERE, '..', 'level_cli.mjs'), path.join(HERE, 'fixtures', 'scale.musicxml')]).toString().trim();
  assert.equal(out, 'beginner');
});
