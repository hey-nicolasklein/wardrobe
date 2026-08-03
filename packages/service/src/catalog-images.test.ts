import assert from 'node:assert/strict';
import test from 'node:test';

import sharp from 'sharp';

import {
  CatalogImageError,
  cropGenerationReference,
  normalizeSourceForProvider,
  removeValidatedChromaBackground,
} from './catalog-images.js';

async function keyedFixture(background: string): Promise<Buffer> {
  return sharp({
    create: { width: 816, height: 816, channels: 3, background },
  })
    .composite([
      {
        input: await sharp({
          create: { width: 260, height: 360, channels: 3, background: '#cc2233' },
        })
          .png()
          .toBuffer(),
        left: 278,
        top: 228,
      },
    ])
    .png()
    .toBuffer();
}

test('normalizes orientation and crops reviewed boxes with context', async () => {
  const oriented = await sharp({
    create: { width: 120, height: 240, channels: 3, background: '#445566' },
  })
    .withMetadata({ orientation: 6 })
    .jpeg()
    .toBuffer();
  const normalized = await normalizeSourceForProvider(oriented);
  const normalizedMetadata = await sharp(normalized).metadata();
  assert.deepEqual(
    { width: normalizedMetadata.width, height: normalizedMetadata.height, orientation: normalizedMetadata.orientation },
    { width: 240, height: 120, orientation: undefined },
  );

  const crop = await cropGenerationReference(normalized, {
    x: 250,
    y: 250,
    width: 500,
    height: 500,
  });
  const cropMetadata = await sharp(crop).metadata();
  assert.equal(cropMetadata.width, 164);
  assert.equal(cropMetadata.height, 82);
});

test('infers each fixture chroma key and preserves garment pixels', async () => {
  for (const key of ['#00ff00', '#ff00ff', '#0066ff']) {
    const result = await removeValidatedChromaBackground(await keyedFixture(key));
    assert.equal(result.resolvedChromaKey, key);
    const { data, info } = await sharp(result.transparentPng)
      .ensureAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });
    assert.equal(data[3], 0);
    const garmentOffset = (400 * info.width + 400) * info.channels;
    assert.equal(data[garmentOffset + 3], 255);
    assert.ok(data[garmentOffset]! > data[garmentOffset + 1]!);
  }
});

test('rejects a non-uniform provider border', async () => {
  const fixture = await sharp({
    create: { width: 816, height: 816, channels: 3, background: '#00ff00' },
  })
    .composite([
      {
        input: await sharp({
          create: { width: 408, height: 816, channels: 3, background: '#0088ff' },
        })
          .png()
          .toBuffer(),
        left: 408,
        top: 0,
      },
    ])
    .png()
    .toBuffer();
  await assert.rejects(
    removeValidatedChromaBackground(fixture),
    (error: unknown) =>
      error instanceof CatalogImageError && error.category === 'chroma-validation',
  );
});
