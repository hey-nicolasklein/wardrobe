import { readdir, readFile, rm, writeFile } from 'node:fs/promises';
import sharp from 'sharp';

// Keep the native launcher and TestFlight artwork in sync with the web icon.
// iOS applies its own corner mask and scales the single 1024px source down.
// Dark and tinted variants are recoloured explicitly: letting iOS derive them
// from the light icon turns the forest F into grey on grey.
const sourceUrl = new URL('../../web/public/icon.svg', import.meta.url);
const catalogUrl = new URL('../ios/Runner/Assets.xcassets/AppIcon.appiconset/', import.meta.url);
const source = (await readFile(sourceUrl, 'utf8')).replace(/\s+rx="[^"]*"/, '');

const recolor = (svg, colors) =>
  Object.entries(colors).reduce((out, [from, to]) => out.replaceAll(`"${from}"`, `"${to}"`), svg);

const variants = [
  { filename: 'AppIcon.png', appearance: null, svg: source, opaque: true },
  {
    // Transparent background so iOS draws its own dark backdrop.
    filename: 'AppIcon-Dark.png',
    appearance: 'dark',
    svg: recolor(source, { '#f6f5f1': 'none', '#344d3f': '#f6f5f1', '#c39a62': '#d9b483' }),
    opaque: false,
  },
  {
    // Grayscale on black: iOS maps luminance to the user's tint.
    filename: 'AppIcon-Tinted.png',
    appearance: 'tinted',
    svg: recolor(source, { '#f6f5f1': '#000000', '#344d3f': '#ffffff', '#c39a62': '#b3b3b3' }),
    opaque: true,
  },
];

for (const file of await readdir(catalogUrl)) {
  if (file.endsWith('.png')) await rm(new URL(file, catalogUrl));
}

for (const { filename, svg, opaque } of variants) {
  let image = sharp(Buffer.from(svg), { density: 576 }).resize(1024, 1024);
  if (opaque) image = image.removeAlpha();
  await writeFile(new URL(filename, catalogUrl), await image.png().toBuffer());
}

const images = variants.map(({ filename, appearance }) => ({
  ...(appearance && { appearances: [{ appearance: 'luminosity', value: appearance }] }),
  filename,
  idiom: 'universal',
  platform: 'ios',
  size: '1024x1024',
}));
await writeFile(
  new URL('Contents.json', catalogUrl),
  `${JSON.stringify({ images, info: { author: 'xcode', version: 1 } }, null, 2)}\n`,
);

console.log(`Generated light, dark and tinted iOS icons from apps/web/public/icon.svg.`);
