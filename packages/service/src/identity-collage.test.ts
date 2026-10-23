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

test('collage assembly rejects zero or more than four photos', async () => {
  await assert.rejects(createIdentityCollage([]));
  await assert.rejects(createIdentityCollage(Array(5).fill(Buffer.alloc(0))));
});
