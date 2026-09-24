import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

import sharp from 'sharp';

// Compact references cut look generation cost by roughly 70% without a visible
// quality loss in our comparison runs.
export const garmentReferenceCollageWidth = 512;
export const garmentReferenceCollageHeight = 256;
const garmentReferenceBoardEdge = 512;

const gutterWidth = 4;
const tileWidth = (garmentReferenceCollageWidth - gutterWidth) / 2;
const background = '#f3f3f1';
const gutter = '#d1d1cc';

async function tile(reference: Uint8Array, width: number, height: number) {
  return sharp(reference, { failOn: 'error', limitInputPixels: 40_000_000 })
    .rotate()
    .resize(width, height, {
      fit: 'contain',
      background,
    })
    .flatten({ background })
    .png()
    .toBuffer();
}

// One generated shelf view and its cropped source photo travel as one provider
// reference. This gives the model both a clean silhouette and the original
// garment details. Dropping the shelf view noticeably hurt garment fidelity.
export async function createGarmentReferenceCollage(
  shelfImage: Uint8Array,
  originalImage: Uint8Array,
) {
  const [shelfTile, originalTile] = await Promise.all([
    tile(shelfImage, tileWidth, garmentReferenceCollageHeight),
    tile(originalImage, tileWidth, garmentReferenceCollageHeight),
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

// Bundles several garment collages into one row-major, two-column board so a
// look sends a single garment reference regardless of how many pieces it has.
export async function createGarmentReferenceBoard(references: Uint8Array[]) {
  if (!references.length) throw new Error('A garment reference board needs one garment.');
  if (references.length === 1) return Buffer.from(references[0]!);
  const metadata = await sharp(references[0]!).metadata();
  const aspectRatio = metadata.width! / metadata.height!;
  const columns = 2;
  const rows = Math.ceil(references.length / columns);
  const width = garmentReferenceBoardEdge;
  const height = Math.min(garmentReferenceBoardEdge, Math.ceil((width / columns / aspectRatio) * rows));
  const renderedCellHeight = Math.max(1, Math.floor(height / rows));
  const renderedCellWidth = Math.floor(width / columns);
  const tiles = await Promise.all(references.map((reference) => tile(reference, renderedCellWidth, renderedCellHeight)));
  return sharp({
    create: {
      width,
      height,
      channels: 3,
      background,
    },
  })
    .composite(tiles.map((input, index) => ({
      input,
      left: (index % columns) * renderedCellWidth,
      top: Math.floor(index / columns) * renderedCellHeight,
    })))
    .png()
    .toBuffer();
}

function safeFilePart(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'garment';
}

function escapeHtml(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

export async function writeGarmentReferenceDebugGallery(input: {
  directory: string;
  lookId: string;
  garments: Array<{ id: string; name: string; collage: Uint8Array }>;
}) {
  await mkdir(input.directory, { recursive: true });
  const images = await Promise.all(input.garments.map(async (garment, index) => {
    const fileName = `${index + 1}-${safeFilePart(garment.name)}-${garment.id}.png`;
    await writeFile(path.join(input.directory, fileName), garment.collage);
    return { fileName, name: garment.name };
  }));
  const gallery = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>FORM garment references</title><style>body{font:16px system-ui;margin:24px;background:#f3f3f1;color:#171714}main{display:grid;gap:24px;max-width:1024px;margin:auto}figure{margin:0}img{display:block;width:100%;border-radius:12px}figcaption{margin-top:8px;font-weight:600}</style></head>
<body><main><h1>Garment references</h1><p>Look ${escapeHtml(input.lookId)}</p>${images.map(({ fileName, name }) => `<figure><img src="./${fileName}" alt="${escapeHtml(name)}"><figcaption>${escapeHtml(name)}</figcaption></figure>`).join('')}</main></body></html>`;
  await writeFile(path.join(input.directory, 'index.html'), gallery);
  return images.map(({ fileName }) => fileName);
}
