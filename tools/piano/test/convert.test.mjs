// Tests of the shared converter (site/tools/piano/convert.mjs) under Node: node --test (in tools/piano)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { convert, pack, unpack, W, H, ROW } from '../../../site/tools/piano/convert.mjs';
import { nodeToolkit, nodeRaster, nodeDeflate, nodeInflate } from '../node_raster.mjs';

const FIX = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures');
const tk = await nodeToolkit();
const cache = {};
async function convertFixture(name) {
  if (!cache[name]) {
    const data = fs.readFileSync(path.join(FIX, name), 'utf8');
    cache[name] = await convert(tk, nodeRaster, { name, data }, { title: name });
  }
  return cache[name];
}

test('scale: one page, right sizes, all onsets', async () => {
  const r = await convertFixture('scale.musicxml');
  assert.equal(W, 800); assert.equal(H, 440); assert.equal(ROW, 100);
  assert.equal(r.pages.length, 1);
  assert.equal(r.pages[0].length, 440 * 100);
  const on = r.map.onsets;
  assert.deepEqual(on.slice(0, 8).map(o => o[5]), [[60], [62], [64], [65], [67], [69], [71], [72]]);
  assert.deepEqual(on[0][6], [48, 55]);                       // LH chord C3+G3 at t=0
  assert.ok(on.every(o => o[3] >= 0 && o[3] < 800 && o[4] >= 0 && o[4] < 440));
  assert.ok(on.every((o, i) => i === 0 || o[0] > on[i - 1][0]));
  assert.equal(r.map.bars.length, 4);
  assert.ok(on.every(o => o[1] >= 1 && o[1] <= 4 && o[2] === 1));
  assert.ok(r.pages[0].some(b => b !== 0), 'the page has black pixels');
});

test('long: ≥3 pages, turn points inside each page', async () => {
  const r = await convertFixture('long.musicxml');
  assert.ok(r.pages.length >= 3);
  assert.equal(r.map.turn.length, r.pages.length);
  r.map.turn.forEach(([s, b], i) => {
    assert.equal(r.map.onsets[s - 1][2], i + 1);
    assert.equal(r.map.onsets[b - 1][2], i + 1);
    assert.ok(b >= s);
  });
  const pages = r.map.onsets.map(o => o[2]);
  assert.ok(pages.every((p, i) => i === 0 || p >= pages[i - 1]), 'pages in order');
  assert.equal(r.map.onsets.length, 64 * 4);                  // RH quarters; LH halves share their onsets
});

test('repeat: unfolded', async () => {                         // 2 bars of 4 quarters inside repeat signs
  const on = (await convertFixture('repeat.musicxml')).map.onsets;
  assert.equal(on.length, 16);
  assert.deepEqual(on[8][5], on[0][5]); assert.equal(on[8][1], on[0][1]);   // same pitches, same bar
  assert.ok(on.every((o, i) => i === 0 || o[0] > on[i - 1][0]));
});

test('abc input converts', async () => {
  const on = (await convertFixture('tune.abc')).map.onsets;
  assert.equal(on.length, 16);
  assert.deepEqual(on[0][5], [60]);
});

test('pack/unpack round trip, every compressed page < 65536', async () => {
  const r = await convertFixture('long.musicxml');
  const bytes = await pack(r, nodeDeflate);
  assert.equal(new TextDecoder().decode(bytes.slice(0, 8)), 'XTSCORE1');
  const u = await unpack(bytes, nodeInflate);
  assert.equal(u.header.title, 'long.musicxml');
  assert.deepEqual(u.pages[2], r.pages[2]);
  assert.deepEqual(u.map, r.map);
  u.header.pages.forEach(([o, l]) => assert.ok(l < 65536));
});


test('tempo marks stripped without losing music (a self-closing tempo before a written one)', async () => {
  const r = await convertFixture('tempos.musicxml');
  assert.equal(r.map.bars.length, 4);
  assert.equal(r.map.onsets.length, 16);
});
