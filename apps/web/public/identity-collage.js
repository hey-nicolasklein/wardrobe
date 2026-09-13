// Keep in sync with packages/service/src/identity-collage.ts.
export const collageWidth = 864;
export const collageHeight = 1536;
export function collageLayout(count) {
  if (!Number.isInteger(count) || count < 1 || count > 4)
    throw new Error('Bitte wähle ein bis vier Fotos.');
  if (count === 1) return [{ left: 0, top: 0, width: collageWidth, height: collageHeight }];
  if (count === 2) return [0, 1].map((row) => ({ left: 0, top: row * 768, width: 864, height: 768 }));
  if (count === 3) return [
    { left: 0, top: 0, width: 864, height: 768 },
    { left: 0, top: 768, width: 432, height: 768 },
    { left: 432, top: 768, width: 432, height: 768 },
  ];
  return [0, 1, 2, 3].map((i) => ({ left: (i % 2) * 432, top: Math.floor(i / 2) * 768, width: 432, height: 768 }));
}

export function cropBounds(imageWidth, imageHeight, tile, crop) {
  const scale = Math.max(tile.width / imageWidth, tile.height / imageHeight) * crop.zoom;
  const width = tile.width / scale, height = tile.height / scale;
  return { x: (imageWidth - width) * crop.x, y: (imageHeight - height) * crop.y, width, height };
}

export function drawCrop(canvas, image, tile, crop) {
  const bounds = cropBounds(image.naturalWidth, image.naturalHeight, tile, crop);
  canvas.width = tile.width;
  canvas.height = tile.height;
  const context = canvas.getContext('2d');
  context.fillStyle = '#fff';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(image, bounds.x, bounds.y, bounds.width, bounds.height, 0, 0, tile.width, tile.height);
}

export async function canvasJpeg(canvas) {
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.95));
  if (!blob) throw new Error('Der Ausschnitt konnte nicht gespeichert werden.');
  return blob;
}
