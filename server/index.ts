import { randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { runCodex } from './codex';
import { enqueueGarmentJob, GARMENT_KINDS, garmentJobFile, getGarmentJob, initialiseGarmentPrototype, listGarmentJobs, type GarmentKind } from './garmentPrototype';
import { editImage } from './openai';

const app = new Hono();
const runtimeDir = path.join(tmpdir(), 'form-wardrobe-poc');
await mkdir(runtimeDir, { recursive: true });
await initialiseGarmentPrototype();

app.onError((error, c) => {
  console.error(error);
  return c.json({ error: error instanceof Error ? error.message : 'Unexpected error' }, 500);
});

app.get('/api/health', (c) => c.json({ ok: true }));

app.get('/api/prototype/garment-jobs', (c) => c.json({ jobs: listGarmentJobs() }));

app.get('/api/prototype/garment-jobs/:id', (c) => {
  const job = getGarmentJob(c.req.param('id'));
  return job ? c.json({ job }) : c.json({ error: 'Job not found' }, 404);
});

app.post('/api/prototype/garment-jobs', async (c) => {
  const body = await c.req.parseBody();
  const image = body.image;
  const garment = body.garment;
  if (!(image instanceof File) || !image.type.startsWith('image/')) return c.json({ error: 'Choose an image' }, 400);
  if (typeof garment !== 'string' || !GARMENT_KINDS.includes(garment as GarmentKind)) return c.json({ error: 'Choose a garment type' }, 400);
  if (image.size > 15 * 1024 * 1024) return c.json({ error: 'Keep the source image under 15 MB' }, 400);
  return c.json({ job: await enqueueGarmentJob(image, garment as GarmentKind) }, 202);
});

app.get('/api/prototype/garment-jobs/:id/files/:filename', async (c) => {
  const filename = c.req.param('filename');
  const file = garmentJobFile(c.req.param('id'), filename);
  if (!file) return c.notFound();
  const stream = Readable.toWeb(createReadStream(file)) as ReadableStream;
  const type = filename.endsWith('.png') ? 'image/png' : filename.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
  return new Response(stream, { headers: { 'content-type': type, 'cache-control': 'no-store' } });
});

app.post('/api/import-product', async (c) => {
  const body = (await c.req.json()) as { url?: string };
  if (!body.url) return c.json({ error: 'Paste a product or image URL' }, 400);
  const url = new URL(body.url);
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return c.json({ error: 'Only web URLs are supported' }, 400);
  if (/\.(png|jpe?g|webp)(\?.*)?$/i.test(url.pathname + url.search)) {
    return c.json({ name: 'Imported piece', brand: url.hostname.replace(/^www\./, ''), image: url.toString(), url: url.toString() });
  }

  const response = await fetch(url, { headers: { 'user-agent': 'Mozilla/5.0 (compatible; FORM wardrobe prototype)' } });
  if (!response.ok) throw new Error(`The shop blocked the import (${response.status}). Add the image directly instead.`);
  const html = await response.text();
  const meta = (property: string) => {
    const escaped = property.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const first = html.match(new RegExp(`<meta[^>]+(?:property|name)=["']${escaped}["'][^>]+content=["']([^"']+)`, 'i'));
    const second = html.match(new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']${escaped}["']`, 'i'));
    return (first?.[1] || second?.[1] || '').replace(/&amp;/g, '&');
  };
  const image = meta('og:image') || meta('twitter:image');
  if (!image) throw new Error('No product image found. Copy the product image address and try that instead.');
  const site = meta('og:site_name') || url.hostname.replace(/^www\./, '');
  const title = meta('og:title') || 'Imported piece';
  return c.json({ name: title.split('|')[0].trim(), brand: site, image: new URL(image, url).toString(), url: url.toString() });
});

app.post('/api/generate-character', async (c) => {
  const body = (await c.req.json()) as { images?: string[]; description?: string; currentImage?: string };
  if (!body.images || body.images.length < 2) return c.json({ error: 'Add at least two photos of yourself' }, 400);
  if (body.images.length > 5) return c.json({ error: 'A fitting profile supports up to five reference photos' }, 400);
  const references = await Promise.all(body.images.map((image, index) => materialize(image, `person-${index}`)));
  const current = body.currentImage ? await materialize(body.currentImage, 'current-profile') : null;
  const inputs = current ? [current, ...references] : references;
  const filename = `${randomUUID()}.png`;
  const output = path.join(runtimeDir, filename);
  const mode = current
    ? 'Image 1 is the existing fitting profile to revise. Keep its identity and contact-sheet structure; apply only the requested changes.'
    : 'Create the first fitting profile from these reference photos.';
  const result = await editImage(inputs, `${mode}

Create a clean photorealistic fitting-profile contact sheet of the same unmistakably adult person. Preserve identity, facial features, natural body proportions, skin tone, hair, and distinguishing features across every panel. Show four useful views in one coherent vertical image: full-body front, relaxed three-quarter, clean side profile, and a natural face close-up. The person wears a fitted plain off-white T-shirt, straight dark trousers, and simple neutral shoes. Warm light-gray studio, soft even light, consistent scale, no text, no labels, no decorative collage elements.

Requested profile details or revision: ${body.description?.trim() || 'Keep the person natural and faithful to the references.'}`);
  await writeFile(output, result);
  return c.json({ image: `/api/generated/${filename}` });
});

app.post('/api/generate-look', async (c) => {
  const body = (await c.req.json()) as {
    characterImage?: string;
    items?: Array<{ name: string; category: string; image: string }>;
    note?: string;
  };
  if (!body.characterImage) return c.json({ error: 'Create your fitting profile first' }, 400);
  if (!body.items?.length) return c.json({ error: 'Add at least one piece to the look' }, 400);
  const character = await materialize(body.characterImage, 'character');
  const itemFiles = await Promise.all(body.items.slice(0, 8).map((item, index) => materialize(item.image, `piece-${index}`)));
  const filename = `${randomUUID()}.png`;
  const output = path.join(runtimeDir, filename);
  const manifest = body.items.map((item, index) => `Reference ${index + 2}: ${item.category} — ${item.name}`).join('\n');
  const result = await editImage(
    [character, ...itemFiles].slice(0, 5),
    `Create one photorealistic full-body fashion photograph. Image 1 is the fitting profile: preserve only that person's identity, face, hair, body proportions and skin tone. Remaining images are clothing references: copy only the garments, never any model, face, body, pose, or background shown in them. Dress the person in all listed pieces with accurate colors, material, cut, details, and layering.\n${manifest}\nCreative direction: ${body.note || 'relaxed everyday street style, natural standing pose'}. Believable smartphone fashion photography, soft daylight, uncluttered city background, vertical composition, no text, no collage.`,
  );
  await writeFile(output, result);
  return c.json({ image: `/api/generated/${filename}` });
});

app.post('/api/recommend-items', async (c) => {
  const body = (await c.req.json()) as {
    image?: string;
    items?: Array<{ name: string; brand: string; category: string }>;
  };
  if (!body.image) return c.json({ error: 'Add an outfit photo first' }, 400);
  const look = await materialize(body.image, 'look');
  const linked = body.items?.length
    ? body.items.map((item) => `- ${item.category}: ${item.brand} ${item.name}`).join('\n')
    : '- No wardrobe items were linked';
  const result = await runCodex(
    `Study the attached outfit photo as a pragmatic personal stylist. The user has explicitly linked these items already:\n${linked}\n\nSuggest at most 3 complementary clothing or accessory pieces that are NOT already linked and would make this outfit more versatile or complete. Do not claim an exact brand or product match from the photo. Prefer concrete, searchable descriptions with color/material, such as "dark brown suede overshirt". If the image or outfit is too unclear, return fewer suggestions or none.\n\nReturn ONLY valid JSON with this exact shape and no markdown: {"suggestions":[{"name":"...","category":"Tops|Bottoms|Outerwear|Shoes|Accessories","confidence":0.0,"reason":"one short sentence"}]}`,
    [look],
    runtimeDir,
  );
  const json = result.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();
  let parsed: { suggestions?: Array<{ name?: unknown; category?: unknown; confidence?: unknown; reason?: unknown }> };
  try {
    parsed = JSON.parse(json);
  } catch {
    throw new Error('Codex did not return usable recommendations. Try another photo.');
  }
  const allowed = new Set(['Tops', 'Bottoms', 'Outerwear', 'Shoes', 'Accessories']);
  const suggestions = (parsed.suggestions ?? []).slice(0, 3).flatMap((suggestion) => {
    if (typeof suggestion.name !== 'string' || typeof suggestion.category !== 'string' || !allowed.has(suggestion.category)) return [];
    return [{
      id: randomUUID(),
      name: suggestion.name,
      category: suggestion.category,
      confidence: Math.max(0, Math.min(1, typeof suggestion.confidence === 'number' ? suggestion.confidence : 0.5)),
      reason: typeof suggestion.reason === 'string' ? suggestion.reason : '',
      status: 'pending' as const,
    }];
  });
  return c.json({ suggestions });
});

app.get('/api/generated/:file', async (c) => {
  const file = c.req.param('file');
  if (!/^[a-f0-9-]+\.png$/i.test(file)) return c.notFound();
  const stream = Readable.toWeb(createReadStream(path.join(runtimeDir, file))) as ReadableStream;
  return new Response(stream, { headers: { 'content-type': 'image/png', 'cache-control': 'no-store' } });
});

async function materialize(source: string, label: string): Promise<string> {
  const filename = `${randomUUID()}-${label}`;
  if (source.startsWith('data:')) {
    const match = source.match(/^data:(image\/[\w.+-]+);base64,(.+)$/);
    if (!match) throw new Error('Unsupported uploaded image');
    const extension = match[1].includes('png') ? '.png' : match[1].includes('webp') ? '.webp' : '.jpg';
    const target = path.join(runtimeDir, filename + extension);
    await writeFile(target, Buffer.from(match[2], 'base64'));
    return target;
  }
  if (source.startsWith('/api/generated/')) return path.join(runtimeDir, path.basename(source));
  const url = new URL(source);
  const response = await fetch(url, { headers: { 'user-agent': 'Mozilla/5.0' } });
  if (!response.ok) throw new Error(`Could not download ${label}`);
  const type = response.headers.get('content-type') || '';
  const extension = type.includes('png') ? '.png' : type.includes('webp') ? '.webp' : '.jpg';
  const target = path.join(runtimeDir, filename + extension);
  await writeFile(target, Buffer.from(await response.arrayBuffer()));
  return target;
}

serve({ fetch: app.fetch, port: 4142 }, (info) => console.log(`FORM AI bridge on http://localhost:${info.port}`));
