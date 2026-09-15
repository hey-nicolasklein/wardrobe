import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

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
