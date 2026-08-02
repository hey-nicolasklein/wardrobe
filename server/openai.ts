import { readFile } from 'node:fs/promises';
import path from 'node:path';

const OPENAI_BASE_URL = 'https://api.openai.com/v1';
const PHOTO_STUDIO_ENV = process.env.PHOTO_STUDIO_ENV ?? path.resolve(process.cwd(), '../photo-studio/.env');

let cachedKey: string | null = null;

async function apiKey(): Promise<string> {
  if (process.env.OPENAI_API_KEY) return process.env.OPENAI_API_KEY;
  if (cachedKey) return cachedKey;

  const env = await readFile(PHOTO_STUDIO_ENV, 'utf8').catch(() => '');
  const line = env.split(/\r?\n/).find((value) => value.trim().startsWith('OPENAI_API_KEY='));
  const value = line?.slice(line.indexOf('=') + 1).trim().replace(/^['"]|['"]$/g, '');
  if (!value) {
    throw new Error('OpenAI is not configured. Set OPENAI_API_KEY or make the photo-studio .env available.');
  }
  cachedKey = value;
  return value;
}

function friendlyOpenAIError(status: number, body: string): Error {
  let message = '';
  try {
    const parsed = JSON.parse(body) as { error?: { message?: string; code?: string } };
    message = parsed.error?.message || '';
  } catch {
    // The fallback below is intentionally user-facing and does not expose raw HTML.
  }
  if (status === 401) return new Error('The OpenAI key was rejected. Check the photo-studio key and try again.');
  if (status === 429) return new Error('Image generation is busy or the account limit was reached. Wait a moment and retry.');
  if (status >= 500) return new Error('OpenAI could not finish the image. Your photos are safe—retry in a moment.');
  if (/safety|moderation|policy/i.test(message)) return new Error('OpenAI could not create this image. Try clear, fully clothed reference photos and neutral wording.');
  return new Error(message || `OpenAI image request failed (${status}).`);
}

export async function editImage(imagePaths: string[], prompt: string): Promise<Buffer> {
  const form = new FormData();
  form.set('model', 'gpt-image-2');
  form.set('prompt', prompt);
  form.set('quality', 'high');
  form.set('size', '1024x1536');
  form.set('output_format', 'png');
  form.set('moderation', 'low');

  for (const [index, imagePath] of imagePaths.entries()) {
    const bytes = await readFile(imagePath);
    const extension = path.extname(imagePath).toLowerCase();
    const type = extension === '.png' ? 'image/png' : extension === '.webp' ? 'image/webp' : 'image/jpeg';
    form.append('image[]', new Blob([bytes], { type }), `reference-${index + 1}${extension || '.jpg'}`);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 4 * 60 * 1000);
  let response: Response;
  try {
    response = await fetch(`${OPENAI_BASE_URL}/images/edits`, {
      method: 'POST',
      headers: { authorization: `Bearer ${await apiKey()}` },
      body: form,
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') throw new Error('Image generation took too long. Retry when your connection is stable.');
    throw new Error('Could not reach OpenAI. Check the connection and try again.');
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) throw friendlyOpenAIError(response.status, await response.text());
  const result = (await response.json()) as { data?: Array<{ b64_json?: string }> };
  const base64 = result.data?.[0]?.b64_json;
  if (!base64) throw new Error('OpenAI finished without returning an image. Retry this draft.');
  return Buffer.from(base64, 'base64');
}
