import type { GeneratedLookSettings, LookSuggestion, WardrobeItem } from './types';

export type GarmentKind = 'top' | 'pants' | 'skirt' | 'dress' | 'shoes' | 'bag' | 'hat' | 'scarf';
export interface GarmentJob {
  id: string;
  garment: GarmentKind;
  status: 'queued' | 'processing' | 'complete' | 'failed';
  progress: string;
  createdAt: string;
  updatedAt: string;
  original: string;
  sticker?: string;
  crop?: { x: number; y: number; width: number; height: number; sourceWidth: number; sourceHeight: number };
  edgeVersion?: number;
  error?: string;
}

async function json<T>(response: Response): Promise<T> {
  const body = (await response.json()) as T & { error?: string };
  if (!response.ok) throw new Error(body.error || `Request failed (${response.status})`);
  return body;
}

export async function importProduct(url: string): Promise<Partial<WardrobeItem>> {
  return json(await fetch('/api/import-product', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ url }),
  }));
}

export async function generateCharacter(images: string[], description: string, currentImage?: string): Promise<{ image: string }> {
  return json(await fetch('/api/generate-character', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ images, description, currentImage }),
  }));
}

export async function generateTryOn(settings: GeneratedLookSettings): Promise<{ image: string }> {
  return json(await fetch('/api/generate-look', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      ...settings,
      items: settings.items.filter((item): item is WardrobeItem & { image: string } => Boolean(item.image)).map(({ name, category, image }) => ({ name, category, image })),
    }),
  }));
}

export async function recommendItems(image: string, linkedItems: WardrobeItem[]): Promise<{ suggestions: LookSuggestion[] }> {
  return json(await fetch('/api/recommend-items', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      image,
      items: linkedItems.map(({ name, brand, category }) => ({ name, brand, category })),
    }),
  }));
}

export async function createGarmentJob(image: File, garment: GarmentKind): Promise<{ job: GarmentJob }> {
  const body = new FormData();
  body.set('image', image);
  body.set('garment', garment);
  return json(await fetch('/api/prototype/garment-jobs', { method: 'POST', body }));
}

export async function loadGarmentJob(id: string): Promise<{ job: GarmentJob }> {
  return json(await fetch(`/api/prototype/garment-jobs/${id}`));
}

export async function loadGarmentJobs(): Promise<{ jobs: GarmentJob[] }> {
  return json(await fetch('/api/prototype/garment-jobs'));
}
