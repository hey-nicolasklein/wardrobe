import sharp from 'sharp';

import type { NormalizedBoundingBox } from '@form/contracts';

const maximumInputPixels = 40_000_000;
const referenceJpegQuality = 92;
const contextPaddingRatio = 0.18;
const keyDistanceTransparent = 12;
const keyDistanceOpaque = 32;

export class CatalogImageError extends Error {
  constructor(
    readonly category: 'conversion' | 'validation' | 'chroma-validation',
    message: string,
  ) {
    super(message);
    this.name = 'CatalogImageError';
  }
}

export async function normalizeSourceForProvider(bytes: Uint8Array): Promise<Buffer> {
  try {
    return await sharp(bytes, { failOn: 'error', limitInputPixels: maximumInputPixels })
      .rotate()
      .jpeg({ quality: referenceJpegQuality, chromaSubsampling: '4:4:4' })
      .toBuffer();
  } catch {
    throw new CatalogImageError(
      'conversion',
      'The Source Photo could not be normalized to an orientation-correct JPEG.',
    );
  }
}

export async function cropGenerationReference(
  normalizedJpeg: Uint8Array,
  box: NormalizedBoundingBox,
): Promise<Buffer> {
  const image = sharp(normalizedJpeg, { failOn: 'error', limitInputPixels: maximumInputPixels });
  const metadata = await image.metadata();
  if (!metadata.width || !metadata.height) {
    throw new CatalogImageError('validation', 'The normalized Source Photo has no dimensions.');
  }

  const targetLeft = Math.floor((box.x / 1_000) * metadata.width);
  const targetTop = Math.floor((box.y / 1_000) * metadata.height);
  const targetWidth = Math.max(1, Math.ceil((box.width / 1_000) * metadata.width));
  const targetHeight = Math.max(1, Math.ceil((box.height / 1_000) * metadata.height));
  const horizontalPadding = Math.ceil(targetWidth * contextPaddingRatio);
  const verticalPadding = Math.ceil(targetHeight * contextPaddingRatio);
  const left = Math.max(0, targetLeft - horizontalPadding);
  const top = Math.max(0, targetTop - verticalPadding);
  const right = Math.min(metadata.width, targetLeft + targetWidth + horizontalPadding);
  const bottom = Math.min(metadata.height, targetTop + targetHeight + verticalPadding);

  return image
    .extract({ left, top, width: Math.max(1, right - left), height: Math.max(1, bottom - top) })
    .jpeg({ quality: referenceJpegQuality, chromaSubsampling: '4:4:4' })
    .toBuffer();
}

function channelMedian(values: number[]): number {
  values.sort((left, right) => left - right);
  return values[Math.floor(values.length / 2)]!;
}

function colorDistance(
  red: number,
  green: number,
  blue: number,
  key: readonly [number, number, number],
): number {
  return Math.sqrt(
    (red - key[0]) ** 2 + (green - key[1]) ** 2 + (blue - key[2]) ** 2,
  );
}

export type ChromaRemovalResult = {
  transparentPng: Buffer;
  resolvedChromaKey: string;
};

export async function removeValidatedChromaBackground(
  keyedPng: Uint8Array,
): Promise<ChromaRemovalResult> {
  let decoded;
  try {
    decoded = await sharp(keyedPng, { failOn: 'error', limitInputPixels: 816 * 816 })
      .ensureAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });
  } catch {
    throw new CatalogImageError('validation', 'The provider result is not a decodable image.');
  }
  const { width, height, channels } = decoded.info;
  if (width !== 816 || height !== 816 || channels !== 4) {
    throw new CatalogImageError(
      'validation',
      `The provider result must be an 816 × 816 RGBA-compatible image; received ${width} × ${height}.`,
    );
  }

  const cornerSize = 12;
  const reds: number[] = [];
  const greens: number[] = [];
  const blues: number[] = [];
  for (const [startX, startY] of [
    [0, 0],
    [width - cornerSize, 0],
    [0, height - cornerSize],
    [width - cornerSize, height - cornerSize],
  ] as const) {
    for (let y = startY; y < startY + cornerSize; y += 1) {
      for (let x = startX; x < startX + cornerSize; x += 1) {
        const offset = (y * width + x) * channels;
        reds.push(decoded.data[offset]!);
        greens.push(decoded.data[offset + 1]!);
        blues.push(decoded.data[offset + 2]!);
      }
    }
  }
  const key = [channelMedian(reds), channelMedian(greens), channelMedian(blues)] as const;

  let borderPixels = 0;
  let uniformBorderPixels = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (x >= 4 && x < width - 4 && y >= 4 && y < height - 4) continue;
      const offset = (y * width + x) * channels;
      borderPixels += 1;
      if (
        colorDistance(
          decoded.data[offset]!,
          decoded.data[offset + 1]!,
          decoded.data[offset + 2]!,
          key,
        ) <= keyDistanceOpaque
      ) {
        uniformBorderPixels += 1;
      }
    }
  }
  if (uniformBorderPixels / borderPixels < 0.985) {
    throw new CatalogImageError(
      'chroma-validation',
      'The generated background is not uniform enough for safe chroma removal.',
    );
  }

  for (let offset = 0; offset < decoded.data.length; offset += channels) {
    const distance = colorDistance(
      decoded.data[offset]!,
      decoded.data[offset + 1]!,
      decoded.data[offset + 2]!,
      key,
    );
    if (distance <= keyDistanceTransparent) {
      decoded.data[offset + 3] = 0;
    } else if (distance < keyDistanceOpaque) {
      decoded.data[offset + 3] = Math.round(
        ((distance - keyDistanceTransparent) /
          (keyDistanceOpaque - keyDistanceTransparent)) *
          255,
      );
    }
  }

  const transparentPng = await sharp(decoded.data, {
    raw: { width, height, channels: 4 },
  })
    .png()
    .toBuffer();
  const resolvedChromaKey = `#${key
    .map((channel) => channel.toString(16).padStart(2, '0'))
    .join('')}`;
  return { transparentPng, resolvedChromaKey };
}
