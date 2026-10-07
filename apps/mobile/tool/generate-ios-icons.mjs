import { readFile, writeFile } from 'node:fs/promises';
import sharp from 'sharp';

// Keep the native launcher and TestFlight artwork in sync with the web icon.
// iOS applies its own corner mask; the source background must fill the square.
const sourceUrl = new URL('../../web/public/icon.svg', import.meta.url);
const catalogUrl = new URL('../ios/Runner/Assets.xcassets/AppIcon.appiconset/', import.meta.url);
const source = (await readFile(sourceUrl, 'utf8')).replace(/\s+rx="[^"]*"/, '');
const { images } = JSON.parse(await readFile(new URL('Contents.json', catalogUrl), 'utf8'));
const sizes = new Map(images.map(({ filename, size, scale }) => [
  filename,
  Number(size.split('x')[0]) * Number(scale.replace('x', '')),
]));

for (const [filename, size] of sizes) {
  const png = await sharp(Buffer.from(source), { density: 288 })
    .resize(size, size)
    .removeAlpha()
    .png()
    .toBuffer();
  await writeFile(new URL(filename, catalogUrl), png);
}

console.log(`Generated ${sizes.size} opaque iOS icons from apps/web/public/icon.svg.`);
