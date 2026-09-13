import assert from 'node:assert/strict';
import test from 'node:test';
import sharp from 'sharp';
import { collageLayout, collageWidth, collageHeight, createIdentityCollage } from './identity-collage.js';

test('every collage pixel belongs to its selected photo for one to four crops', async () => {
  const colors = [[231, 12, 34], [15, 204, 55], [21, 43, 218], [197, 172, 29]];
  for (let count = 1; count <= 4; count++) {
    const layout = collageLayout(count);
    const refs = await Promise.all(layout.map((tile, i) => sharp({ create: {
      width: tile.width, height: tile.height, channels: 3,
      background: { r: colors[i]![0]!, g: colors[i]![1]!, b: colors[i]![2]! },
    } }).png().toBuffer()));
    const result = await createIdentityCollage(refs);
    const { data, info } = await sharp(result).removeAlpha().raw().toBuffer({ resolveWithObject: true });
    assert.equal(info.width, collageWidth);
    assert.equal(info.height, collageHeight);
    for (let y = 0; y < collageHeight; y++) for (let x = 0; x < collageWidth; x++) {
      const matches = layout.flatMap((tile, i) => x >= tile.left && x < tile.left + tile.width && y >= tile.top && y < tile.top + tile.height ? [i] : []);
      assert.equal(matches.length, 1, `pixel ${x},${y} must have exactly one photo`);
      const color = colors[matches[0]!]!;
      const offset = (y * collageWidth + x) * 3;
      for (let c = 0; c < 3; c++) assert.equal(data[offset + c], color[c]);
    }
  }
});

test('browser crop frames match assembly, and zoom and pan never expose empty pixels', async () => {
  const browser = await import(new URL('../../../apps/web/public/identity-collage.js', import.meta.url).href);
  for (let count = 1; count <= 4; count++) {
    assert.deepEqual(browser.collageLayout(count), collageLayout(count));
    for (const tile of collageLayout(count)) {
      for (const [width, height] of [[4032, 3024], [800, 1600], [64, 32]]) {
        for (const zoom of [1, 2, 6]) for (const x of [0, 0.5, 1]) for (const y of [0, 0.5, 1]) {
          const crop = browser.cropBounds(width, height, tile, { zoom, x, y });
          assert.ok(crop.x >= 0 && crop.y >= 0);
          assert.ok(crop.x + crop.width <= width! + 1e-8);
          assert.ok(crop.y + crop.height <= height! + 1e-8);
          assert.ok(Math.abs(crop.width / crop.height - tile.width / tile.height) < 1e-8);
        }
      }
    }
  }
  await assert.rejects(createIdentityCollage([]));
  await assert.rejects(createIdentityCollage(Array(5).fill(Buffer.alloc(0))));
});
