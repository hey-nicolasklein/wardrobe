import sharp from 'sharp';

import type { NormalizedBoundingBox } from '@form/contracts';

const maximumInputPixels = 40_000_000;
const referenceJpegQuality = 92;
// Room left around the garment on each side, as a share of its longer edge.
const contextPaddingRatio = 0.25;
const keyDistanceTransparent = 12;
const keyDistanceOpaque = 32;
// How many pixels in from the matte edge to decontaminate chroma spill (the halo).
const spillEdgeRadius = 6;

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

  // A square window centred on the garment, sized from its longer edge. Padding
  // each axis by a share of its own length starved flat boxes: a 462x140 pair of
  // shorts got generous room sideways and almost none above the waistband, so
  // necklines and hems fell outside the reference and the model invented them.
  // Square also matches the square output, which keeps the garment's pixels.
  const centerX = ((box.x + box.width / 2) / 1_000) * metadata.width;
  const centerY = ((box.y + box.height / 2) / 1_000) * metadata.height;
  const longEdge = Math.max(
    (box.width / 1_000) * metadata.width,
    (box.height / 1_000) * metadata.height,
  );
  const desired = Math.round(longEdge * (1 + 2 * contextPaddingRatio));
  // Clamped per axis, not by one shared side. A single side capped at the
  // shorter image edge would cut a garment that is taller than the photo is
  // wide — a full-length coat in a portrait shot — so the window gives up
  // squareness only as far as the photo forces it, and never drops the box.
  const cropWidth = Math.max(1, Math.min(desired, metadata.width));
  const cropHeight = Math.max(1, Math.min(desired, metadata.height));
  const left = Math.round(
    Math.min(Math.max(0, centerX - cropWidth / 2), metadata.width - cropWidth),
  );
  const top = Math.round(
    Math.min(Math.max(0, centerY - cropHeight / 2), metadata.height - cropHeight),
  );

  return image
    .extract({ left, top, width: cropWidth, height: cropHeight })
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

  // Coarse matte by colour distance: garment opaque, background transparent,
  // with a narrow feather. Snapshot it so the edge pass reads a stable matte.
  const matte = new Uint8Array(width * height);
  for (let index = 0; index < matte.length; index += 1) {
    const offset = index * channels;
    const distance = colorDistance(
      decoded.data[offset]!,
      decoded.data[offset + 1]!,
      decoded.data[offset + 2]!,
      key,
    );
    matte[index] =
      distance <= keyDistanceTransparent
        ? 0
        : distance < keyDistanceOpaque
          ? Math.round(
              ((distance - keyDistanceTransparent) /
                (keyDistanceOpaque - keyDistanceTransparent)) *
                255,
            )
          : 255;
    decoded.data[offset + 3] = matte[index]!;
  }

  // Distance keying alone leaves a tinted ring on soft edges: a blend of garment
  // and background sits far from the pure key colour, so it stays opaque and
  // keeps its chroma tint (the halo). Near the matte edge, re-key by how strongly
  // a pixel leans toward the key colour and un-mix that contribution back out,
  // recovering the true garment colour so the edge fades cleanly over any
  // background. Gated spatially, so a garment body is never touched. spillChannels
  // carry the key (green for #00ff00, red and blue for the #ff00ff fallback);
  // anchorChannels are the garment-bearing rest.
  const keyMax = Math.max(key[0], key[1], key[2]);
  const spillChannels = [0, 1, 2].filter((channel) => key[channel]! > keyMax / 2);
  const anchorChannels = [0, 1, 2].filter((channel) => key[channel]! <= keyMax / 2);
  const spillKey =
    spillChannels.reduce((sum, channel) => sum + key[channel]!, 0) /
    Math.max(1, spillChannels.length);
  const anchorKey = Math.max(0, ...anchorChannels.map((channel) => key[channel]!));
  const keyStrength = spillKey - anchorKey;
  if (anchorChannels.length > 0 && keyStrength > 0) {
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const index = y * width + x;
        if (matte[index] === 0) continue;
        let nearEdge = false;
        for (let dy = -spillEdgeRadius; dy <= spillEdgeRadius && !nearEdge; dy += 1) {
          const ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (let dx = -spillEdgeRadius; dx <= spillEdgeRadius; dx += 1) {
            const nx = x + dx;
            if (nx < 0 || nx >= width) continue;
            if (matte[ny * width + nx] === 0) {
              nearEdge = true;
              break;
            }
          }
        }
        if (!nearEdge) continue;
        const offset = index * channels;
        const spill =
          spillChannels.reduce((sum, channel) => sum + decoded.data[offset + channel]!, 0) /
          spillChannels.length;
        const anchor = Math.max(0, ...anchorChannels.map((channel) => decoded.data[offset + channel]!));
        let coverage = 1 - (spill - anchor) / keyStrength;
        coverage = Math.max(0, Math.min(coverage, matte[index]! / 255));
        if (coverage <= 0) {
          decoded.data[offset + 3] = 0;
          continue;
        }
        for (const channel of [0, 1, 2]) {
          const unmixed =
            (decoded.data[offset + channel]! - (1 - coverage) * key[channel]!) / coverage;
          decoded.data[offset + channel] = Math.max(0, Math.min(255, Math.round(unmixed)));
        }
        decoded.data[offset + 3] = Math.round(coverage * 255);
      }
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
