import assert from 'node:assert/strict';
import test from 'node:test';

import sharp from 'sharp';

import { removeValidatedChromaBackground } from './catalog-images.js';
import { OpenAICatalogProvider, shelfImagePromptVersion } from './catalog-provider.js';

const enabled = process.env.FORM_RUN_OPENAI_SMOKE === 'true';

test('live OpenAI detection and image edit endpoints accept the production contracts', { skip: !enabled }, async () => {
  const apiKey = process.env.OPENAI_API_KEY;
  assert.ok(apiKey, 'OPENAI_API_KEY is required for the deliberate paid smoke test.');
  const source = await sharp(
    Buffer.from(`<svg width="640" height="640" xmlns="http://www.w3.org/2000/svg">
      <rect width="640" height="640" fill="#f4f1eb"/>
      <path d="M210 150 L285 110 L355 110 L430 150 L510 260 L445 305 L400 245 L400 525 L240 525 L240 245 L195 305 L130 260 Z" fill="#24385f"/>
      <path d="M285 110 Q320 175 355 110" fill="none" stroke="#d9d5ca" stroke-width="12"/>
    </svg>`),
  )
    .jpeg({ quality: 92 })
    .toBuffer();
  const provider = new OpenAICatalogProvider(
    apiKey,
    process.env.OPENAI_API_BASE_URL ?? 'https://api.openai.com/v1',
  );

  const detection = await provider.detect({
    jpegBytes: source,
    model: process.env.OPENAI_DETECTION_MODEL ?? 'gpt-5.4-mini',
  });
  assert.ok(detection.requestId);
  assert.ok(detection.detections.length > 0, 'Live detection returned no wearable proposal.');

  const generated = await provider.generate({
    referenceJpeg: source,
    metadata: {
      name: 'Navy long-sleeve top',
      category: 'top',
      colors: ['navy'],
      notes: null,
    },
    model: 'gpt-image-2',
    quality: 'low',
    size: '816x816',
    promptVersion: shelfImagePromptVersion,
  });
  assert.ok(generated.requestId);
  assert.ok(generated.usage.textInputTokens >= 0);
  assert.ok(generated.usage.imageInputTokens > 0);
  assert.ok(generated.usage.outputTokens > 0);
  const processed = await removeValidatedChromaBackground(generated.pngBytes);
  assert.match(processed.resolvedChromaKey, /^#[0-9a-f]{6}$/);
});
