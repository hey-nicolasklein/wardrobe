import assert from 'node:assert/strict';
import test from 'node:test';

import sharp from 'sharp';

import {
  createGarmentReferenceCollage,
  garmentReferenceCollageHeight,
  garmentReferenceCollageWidth,
} from './garment-reference-collage.js';

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
  assert.deepEqual(pixel(255, 256), [225, 20, 40]);
  assert.deepEqual(pixel(768, 256), [24, 59, 223]);
  assert.deepEqual(pixel(511, 256), [209, 209, 204]);
});
