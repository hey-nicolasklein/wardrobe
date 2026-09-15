import { mkdir, writeFile } from 'node:fs/promises';
import sharp from 'sharp';
const base = process.env.LIKENESS_APP_URL || 'http://127.0.0.1:4143';
const folder = new URL('../../.prototype-data/likeness-lab/wardrobe/', import.meta.url);
await mkdir(folder, { recursive: true });
const response = await fetch(`${base}/v1/wardrobe-items`);
if (!response.ok) throw Error(`Wardrobe read failed: ${response.status}`);
const { wardrobeItems } = await response.json();
const items = [];
for (const item of wardrobeItems.filter(i => i.state !== 'archived' && i.currentShelfImageVersionId)) {
  const image = await fetch(`${base}/v1/wardrobe-items/${item.id}/preview`);
  if (!image.ok) throw Error(`Preview failed for ${item.id}: ${image.status}`);
  await writeFile(new URL(`${item.id}.png`, folder), await sharp(Buffer.from(await image.arrayBuffer())).png().toBuffer());
  items.push({ id: item.id, ...item.metadata, state: item.state, shelfImageVersionId: item.currentShelfImageVersionId, image: `/wardrobe/${item.id}.png` });
}
await writeFile(new URL('items.json', folder), JSON.stringify(items, null, 2));
console.log(`Copied ${items.length} wardrobe previews and metadata. No wardrobe writes.`);
