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

  // 120x60 box in a 240x120 image wants a 180px window; the height clamps to
  // the 120px the photo has, the width keeps the full 180.
  const crop = await cropGenerationReference(normalized, {
    x: 250,
    y: 250,
    width: 500,
    height: 500,
  });
  const cropMetadata = await sharp(crop).metadata();
  assert.equal(cropMetadata.width, 180);
  assert.equal(cropMetadata.height, 120);
});

test('keeps a garment taller than the photo is wide', async () => {
  const portrait = await sharp({
    create: { width: 1200, height: 2400, channels: 3, background: '#445566' },
  })
    .jpeg()
    .toBuffer();
  // A full-length coat: 1920px tall in a photo only 1200px wide. Sizing one
  // square side and capping it at the shorter image edge would have produced a
  // 1200px window and sliced 720px off the garment before the paid request.
  const crop = await cropGenerationReference(await normalizeSourceForProvider(portrait), {
    x: 350,
    y: 100,
    width: 300,
    height: 800,
  });
  const cropMetadata = await sharp(crop).metadata();
  assert.ok(
    cropMetadata.height! >= 1920,
    `window must contain the whole garment, got ${cropMetadata.height}`,
  );
  assert.equal(cropMetadata.width, 1200, 'width clamps to the photo');
});

test('gives a flat box room above and below, not just sideways', async () => {
  const wide = await sharp({
    create: { width: 1000, height: 1000, channels: 3, background: '#445566' },
  })
    .jpeg()
    .toBuffer();
  // A shorts-shaped box: wide and short. Padding each axis by its own length
  // used to leave almost no vertical context, cutting off waistbands and hems.
  const crop = await cropGenerationReference(await normalizeSourceForProvider(wide), {
    x: 200,
    y: 600,
    width: 500,
    height: 150,
  });
  const cropMetadata = await sharp(crop).metadata();
  assert.equal(cropMetadata.width, 750, 'square window sized from the long edge');
  assert.equal(cropMetadata.height, 750);
  // The box is 150px tall, so the window carries 600px of context around it.
  assert.ok(
    cropMetadata.height! - 150 > 500,
    'a flat box still gets generous vertical context',
  );
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

test('neutralises the chroma halo on soft edges without dulling a green garment', async () => {
  const softShape = (garment: string) =>
    sharp(
      Buffer.from(
        `<svg width="816" height="816" xmlns="http://www.w3.org/2000/svg"><rect width="816" height="816" fill="#00ff00"/><ellipse cx="408" cy="408" rx="300" ry="330" fill="${garment}"/></svg>`,
      ),
    )
      .png()
      .toBuffer();
  const greenLead = async (transparentPng: Buffer, edgeOnly: boolean) => {
    const { data, info } = await sharp(transparentPng)
      .flatten({ background: '#ffffff' })
      .raw()
      .toBuffer({ resolveWithObject: true });
    let count = 0;
    for (let offset = 0; offset < data.length; offset += info.channels) {
      const [r, g, b] = [data[offset]!, data[offset + 1]!, data[offset + 2]!];
      if (edgeOnly && !(r > 230 && b > 230)) continue; // only the cream body/edge
      if (g - Math.max(r, b) > 12) count += 1;
    }
    return count;
  };

  // A cream garment must leave no green fringe once the halo is neutralised.
  const cream = await removeValidatedChromaBackground(await softShape('#efe9dc'));
  assert.equal(await greenLead(cream.transparentPng, false), 0);

  // A genuinely green garment body must survive: its interior stays green.
  const green = await removeValidatedChromaBackground(await softShape('#2f6b3a'));
  const { data, info } = await sharp(green.transparentPng)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const center = (408 * info.width + 408) * info.channels;
  assert.equal(data[center + 3], 255);
  assert.ok(data[center + 1]! > data[center]! && data[center + 1]! > data[center + 2]!);
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
