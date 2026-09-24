import sharp from 'sharp';

// Keep in sync with the crop frames in apps/web/public/identity-collage.js.
// These dimensions also match the existing character_sheets output_size contract.
export const collageWidth = 864;
export const collageHeight = 1536;
export const collageModel = 'photo-collage-v1';

export function collageLayout(count: number) {
  if (!Number.isInteger(count) || count < 1 || count > 4)
    throw new Error('A collage needs one to four photos.');
  if (count === 1) return [{ left: 0, top: 0, width: collageWidth, height: collageHeight }];
  if (count === 2) return [0, 1].map((row) => ({ left: 0, top: row * 768, width: 864, height: 768 }));
  if (count === 3) return [
    { left: 0, top: 0, width: 864, height: 768 },
    { left: 0, top: 768, width: 432, height: 768 },
    { left: 432, top: 768, width: 432, height: 768 },
  ];
  return [0, 1, 2, 3].map((i) => ({ left: (i % 2) * 432, top: Math.floor(i / 2) * 768, width: 432, height: 768 }));
}

export async function createIdentityCollage(references: Buffer[]) {
  const layout = collageLayout(references.length);
  const tiles = await Promise.all(references.map(async (reference, index) => {
    const tile = layout[index]!;
    return {
      input: await sharp(reference).rotate().resize(tile.width, tile.height, { fit: 'cover' })
        .flatten({ background: '#ffffff' }).png().toBuffer(),
      left: tile.left,
      top: tile.top,
    };
  }));
  return sharp({ create: { width: collageWidth, height: collageHeight, channels: 3, background: '#ffffff' } })
    .composite(tiles).png().toBuffer();
}

/** Shrinks the approved reference without cropping or enlarging it. */
export function compactIdentityReference(reference: Uint8Array) {
  return sharp(reference, { failOn: 'error', limitInputPixels: 40_000_000 })
    .rotate()
    .resize(432, 768, { fit: 'inside', withoutEnlargement: true })
    .png()
    .toBuffer();
}
