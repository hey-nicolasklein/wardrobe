// PROTOTYPE — durable garment-segmentation jobs. Delete or absorb after the preview verdict.
import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pipeline, env, type ImageSegmentationPipeline } from '@huggingface/transformers';
import sharp from 'sharp';

export const GARMENT_KINDS = ['top', 'pants', 'skirt', 'dress', 'shoes', 'bag', 'hat', 'scarf'] as const;
export type GarmentKind = typeof GARMENT_KINDS[number];
export type GarmentJobStatus = 'queued' | 'processing' | 'complete' | 'failed';

export interface GarmentJob {
  id: string;
  garment: GarmentKind;
  status: GarmentJobStatus;
  progress: string;
  createdAt: string;
  updatedAt: string;
  original: string;
  sticker?: string;
  crop?: { x: number; y: number; width: number; height: number; sourceWidth: number; sourceHeight: number };
  edgeVersion?: number;
  error?: string;
}

const LABELS: Record<GarmentKind, string[]> = {
  top: ['Upper-clothes'],
  pants: ['Pants'],
  skirt: ['Skirt'],
  dress: ['Dress'],
  shoes: ['Left-shoe', 'Right-shoe'],
  bag: ['Bag'],
  hat: ['Hat'],
  scarf: ['Scarf'],
};

const dataDir = path.resolve(process.cwd(), '.prototype-data/garment-jobs');
const jobsFile = path.join(dataDir, 'jobs.json');
const modelCache = path.resolve(process.cwd(), '.prototype-data/models');
env.cacheDir = modelCache;

let jobs: GarmentJob[] = [];
let segmenterPromise: Promise<ImageSegmentationPipeline> | null = null;
let workerRunning = false;

export async function initialiseGarmentPrototype() {
  await Promise.all([mkdir(dataDir, { recursive: true }), mkdir(modelCache, { recursive: true })]);
  const stored = JSON.parse(await readFile(jobsFile, 'utf8').catch(() => '[]')) as Array<GarmentJob & { dimmed?: string }>;
  jobs = stored.map((storedJob) => {
    const { dimmed: legacyDimmed, ...job } = storedJob;
    if (legacyDimmed) void unlink(path.join(dataDir, job.id, 'dimmed.png')).catch(() => undefined);
    if (job.status === 'processing') return { ...job, status: 'queued', progress: 'Recovered after server restart' };
    if (job.status === 'complete' && (!job.crop || job.edgeVersion !== 3)) return { ...job, status: 'queued', progress: 'Smoothing garment edges', sticker: undefined };
    return job;
  });
  await persist();
  void runWorker();
}

export function listGarmentJobs() {
  return [...jobs].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

export function getGarmentJob(id: string) {
  return jobs.find((job) => job.id === id);
}

export async function enqueueGarmentJob(file: File, garment: GarmentKind) {
  const id = randomUUID();
  const extension = file.type === 'image/png' ? '.png' : file.type === 'image/webp' ? '.webp' : '.jpg';
  const directory = path.join(dataDir, id);
  await mkdir(directory, { recursive: true });
  const originalFile = `original${extension}`;
  await writeFile(path.join(directory, originalFile), Buffer.from(await file.arrayBuffer()));
  const now = new Date().toISOString();
  const job: GarmentJob = {
    id,
    garment,
    status: 'queued',
    progress: 'Waiting in durable queue',
    createdAt: now,
    updatedAt: now,
    original: `/api/prototype/garment-jobs/${id}/files/${originalFile}`,
  };
  jobs.push(job);
  await persist();
  void runWorker();
  return job;
}

export function garmentJobFile(id: string, filename: string) {
  if (!/^[a-f0-9-]{36}$/i.test(id) || !/^(original\.(?:png|jpe?g|webp)|sticker\.png)$/i.test(filename)) return null;
  return path.join(dataDir, id, filename);
}

async function persist() {
  const temporary = `${jobsFile}.next`;
  await writeFile(temporary, JSON.stringify(jobs, null, 2));
  await rename(temporary, jobsFile);
}

function update(id: string, patch: Partial<GarmentJob>) {
  jobs = jobs.map((job) => job.id === id ? { ...job, ...patch, updatedAt: new Date().toISOString() } : job);
  return persist();
}

async function getSegmenter() {
  const createSegmenter = pipeline as unknown as (
    task: 'image-segmentation',
    model: string,
    options: { dtype: 'fp32'; cache_dir: string },
  ) => Promise<ImageSegmentationPipeline>;
  segmenterPromise ??= createSegmenter('image-segmentation', 'Xenova/segformer_b2_clothes', {
    // This older ONNX export names its quantized file differently than Transformers.js 4 expects.
    // fp32 is larger, but deterministic and compatible for the throwaway server-side POC.
    dtype: 'fp32',
    cache_dir: modelCache,
  });
  return segmenterPromise;
}

async function runWorker() {
  if (workerRunning) return;
  workerRunning = true;
  try {
    for (;;) {
      const job = jobs.find((candidate) => candidate.status === 'queued');
      if (!job) break;
      try {
        await update(job.id, { status: 'processing', progress: 'Loading deterministic clothes model', error: undefined });
        await processJob(job);
      } catch (reason) {
        await update(job.id, {
          status: 'failed',
          progress: 'Stopped',
          error: reason instanceof Error ? reason.message : 'Garment extraction failed',
        });
      }
    }
  } finally {
    workerRunning = false;
  }
}

async function processJob(job: GarmentJob) {
  const directory = path.join(dataDir, job.id);
  const originalPath = path.join(directory, path.basename(job.original));
  const image = sharp(originalPath).rotate();
  const metadata = await image.metadata();
  if (!metadata.width || !metadata.height) throw new Error('Could not read image dimensions');

  await update(job.id, { progress: 'Segmenting clothing pixels' });
  const segmenter = await getSegmenter();
  // This SegFormer checkpoint resolves its own semantic post-processor and returns original-size masks.
  const output = await segmenter(originalPath);
  const selected = output.filter((part) => part.label && LABELS[job.garment].includes(part.label));
  if (!selected.length) throw new Error(`No ${job.garment} pixels were found in this image`);

  const width = selected[0].mask.width;
  const height = selected[0].mask.height;
  const alpha = Buffer.alloc(width * height);
  for (const part of selected) {
    const channels = part.mask.channels;
    for (let pixel = 0; pixel < width * height; pixel += 1) {
      alpha[pixel] = Math.max(alpha[pixel], part.mask.data[pixel * channels]);
    }
  }
  const resizedAlpha = await sharp(alpha, { raw: { width, height, channels: 1 } })
    .resize(metadata.width, metadata.height, { kernel: sharp.kernel.nearest })
    .greyscale()
    .raw()
    .toBuffer();
  const edgeSigma = Math.min(3.2, Math.max(1.1, Math.max(metadata.width, metadata.height) / 1200));
  const mask = await sharp(resizedAlpha, { raw: { width: metadata.width, height: metadata.height, channels: 1 } })
    // Remove isolated one-pixel notches, then feather proportionally to source resolution.
    // Mild midpoint contrast keeps the result crisp without reverting to a binary staircase.
    .median(3)
    .blur(edgeSigma)
    .linear(1.2, -25.5)
    .png()
    .toBuffer();
  const maskLayer = await sharp({
    create: { width: metadata.width, height: metadata.height, channels: 3, background: '#ffffff' },
  }).joinChannel(mask).png().toBuffer();

  await update(job.id, { progress: 'Cropping sticker and saving geometry' });
  const upright = await image.png().toBuffer();
  const stickerPath = path.join(directory, 'sticker.png');
  const isolated = await sharp(upright).ensureAlpha().composite([{ input: maskLayer, blend: 'dest-in' }]).png().toBuffer();
  const crop = contextCrop(resizedAlpha, metadata.width, metadata.height);
  await sharp(isolated).extract({ left: crop.x, top: crop.y, width: crop.width, height: crop.height }).png().toFile(stickerPath);

  await update(job.id, {
    status: 'complete',
    progress: 'Ready to compare',
    sticker: `/api/prototype/garment-jobs/${job.id}/files/sticker.png`,
    crop: { ...crop, sourceWidth: metadata.width, sourceHeight: metadata.height },
    edgeVersion: 3,
  });
}

function contextCrop(alpha: Buffer, width: number, height: number) {
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (alpha[y * width + x] < 128) continue;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
    }
  }
  if (maxX < minX || maxY < minY) throw new Error('The garment mask was empty');
  const garmentWidth = maxX - minX + 1;
  const garmentHeight = maxY - minY + 1;
  const padX = Math.min(180, Math.max(24, Math.round(garmentWidth * 0.18)));
  const padY = Math.min(180, Math.max(24, Math.round(garmentHeight * 0.14)));
  const x = Math.max(0, minX - padX);
  const y = Math.max(0, minY - padY);
  const right = Math.min(width, maxX + 1 + padX);
  const bottom = Math.min(height, maxY + 1 + padY);
  return { x, y, width: right - x, height: bottom - y };
}
