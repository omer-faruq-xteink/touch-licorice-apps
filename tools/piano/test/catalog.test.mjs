// build_catalog.mjs: reviewed entries are built, todo entries get contact sheets, rejected are left out
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildCatalog } from '../build_catalog.mjs';
import { unpack } from '../../../site/tools/piano/convert.mjs';
import { nodeInflate } from '../node_raster.mjs';

const FIX = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures');

test('build: ok built, todo reviewed, rejected skipped', async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pfcat-'));
  const yaml = `pieces:
  - id: scale-study
    src: scale.musicxml
    title: Scale Study
    composer: Test
    license: CC0
    url: https://example.org/scale
    review: ok
  - id: long-piece
    src: long.musicxml
    title: Long Piece
    composer: Test
    license: Public domain
    level: intermediate
    review: ok
  - id: dense-todo
    src: dense.musicxml
    title: Dense
    composer: Test
    license: CC0
    review: todo
  - id: tune-no
    src: tune.abc
    title: Nope
    composer: Trad.
    license: CC0
    review: rejected
`;
  fs.writeFileSync(path.join(tmp, 'catalog.yaml'), yaml);
  const out = path.join(tmp, 'out'), review = path.join(tmp, 'review');
  const r = await buildCatalog({ yamlPath: path.join(tmp, 'catalog.yaml'), srcDir: FIX, outDir: out, reviewDir: review });
  assert.deepEqual(r.built, ['long-piece', 'scale-study']);
  assert.deepEqual(r.toReview, ['dense-todo']);
  const cat = JSON.parse(fs.readFileSync(path.join(out, 'catalog.json'), 'utf8'));
  assert.equal(cat.v, 1);
  assert.deepEqual(cat.pieces.map(p => p.id), ['long-piece', 'scale-study']);
  const s = cat.pieces.find(p => p.id === 'scale-study');
  assert.equal(s.level, 'beginner'); assert.equal(s.composer, 'Test'); assert.equal(s.license, 'CC0'); assert.equal(s.pages, 1);
  assert.equal(cat.pieces.find(p => p.id === 'long-piece').level, 'intermediate');      // the override wins
  const bytes = fs.readFileSync(path.join(out, 'pieces', 'scale-study.xtscore'));
  assert.equal(s.size, bytes.length);
  const u = await unpack(new Uint8Array(bytes), nodeInflate);
  assert.equal(u.header.title, 'Scale Study'); assert.equal(u.header.url, 'https://example.org/scale'); assert.equal(u.header.level, 'beginner');
  const png = fs.readFileSync(path.join(review, 'dense-todo.png'));
  assert.deepEqual([...png.slice(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.ok(!fs.existsSync(path.join(out, 'pieces', 'tune-no.xtscore')));
});
