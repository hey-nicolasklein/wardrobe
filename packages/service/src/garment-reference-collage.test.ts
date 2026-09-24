import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import sharp from 'sharp';

import {
  createGarmentReferenceBoard,
  createGarmentReferenceCollage,
  garmentReferenceCollageHeight,
  garmentReferenceCollageWidth,
  writeGarmentReferenceDebugGallery,
} from './garment-reference-collage.js';

async function dimensions(bytes: Uint8Array) {
  const metadata = await sharp(bytes).metadata();
  return { width: metadata.width, height: metadata.height };
}

test('combines shelf and original images into one stable side-by-side reference', async () => {
  const shelf = await sharp({
    create: { width: 256, height: 512, channels: 4, background: '#e11428' },
  }).png().toBuffer();
  const original = await sharp({
    create: { width: 512, height: 256, channels: 3, background: '#173bdf' },
  }).jpeg().toBuffer();

  const collage = await createGarmentReferenceCollage(shelf, original);
  const { data, info } = await sharp(collage).removeAlpha().raw()
    .toBuffer({ resolveWithObject: true });

  assert.equal(info.width, garmentReferenceCollageWidth);
  assert.equal(info.height, garmentReferenceCollageHeight);
  const pixel = (x: number, y: number) => {
    const offset = (y * info.width + x) * info.channels;
    return Array.from(data.subarray(offset, offset + 3));
  };
  assert.deepEqual(pixel(127, 128), [225, 20, 40]);
  assert.deepEqual(pixel(384, 128), [24, 59, 223]);
  assert.deepEqual(pixel(255, 128), [209, 209, 204]);
});

test('writes an inspectable debug gallery without database storage', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'form-garment-references-'));
  const collage = await sharp({
    create: { width: 16, height: 8, channels: 3, background: '#e11428' },
  }).png().toBuffer();

  const files = await writeGarmentReferenceDebugGallery({
    directory,
    lookId: 'look<&>',
    garments: [{ id: 'item-1', name: 'Red Shirt <Special>', collage }],
  });

  assert.deepEqual(files, ['1-red-shirt-special-item-1.png']);
  assert.deepEqual(await readFile(path.join(directory, files[0]!)), collage);
  const gallery = await readFile(path.join(directory, 'index.html'), 'utf8');
  assert.match(gallery, /Look look&lt;&amp;&gt;/);
  assert.match(gallery, /Red Shirt &lt;Special&gt;/);
});

test('bundles garment references into one capped board', async () => {
  const source = await sharp({
    create: { width: 256, height: 512, channels: 3, background: '#e11428' },
  }).png().toBuffer();
  const collage = await createGarmentReferenceCollage(source, source);
  const board = await createGarmentReferenceBoard([collage, collage, collage, collage, collage, collage]);
  assert.deepEqual(await dimensions(board), { width: 512, height: 384 });
});
