import sharp from 'sharp';

export const garmentReferenceCollageWidth = 1024;
export const garmentReferenceCollageHeight = 512;

const gutterWidth = 8;
const tileWidth = (garmentReferenceCollageWidth - gutterWidth) / 2;
const background = '#f3f3f1';
const gutter = '#d1d1cc';

async function tile(reference: Uint8Array) {
  return sharp(reference, { failOn: 'error', limitInputPixels: 40_000_000 })
    .rotate()
    .resize(tileWidth, garmentReferenceCollageHeight, {
      fit: 'contain',
      background,
    })
    .flatten({ background })
    .png()
    .toBuffer();
}

// One generated shelf view and its cropped source photo travel as one provider
// reference. This preserves the reference count while giving the model both a
// clean silhouette and the original garment details.
export async function createGarmentReferenceCollage(
  shelfImage: Uint8Array,
  originalImage: Uint8Array,
) {
  const [shelfTile, originalTile] = await Promise.all([
    tile(shelfImage),
    tile(originalImage),
  ]);
  return sharp({
    create: {
      width: garmentReferenceCollageWidth,
      height: garmentReferenceCollageHeight,
      channels: 3,
      background: gutter,
    },
  })
    .composite([
      { input: shelfTile, left: 0, top: 0 },
      { input: originalTile, left: tileWidth + gutterWidth, top: 0 },
    ])
    .png()
    .toBuffer();
}
