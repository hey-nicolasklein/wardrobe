import assert from 'node:assert/strict';
import test from 'node:test';

import sharp from 'sharp';

import {
  CatalogProviderError,
  OpenAICatalogProvider,
  ReplayCatalogProvider,
  shelfImagePromptVersion,
} from './catalog-provider.js';
import {
  calculateCostMicrounits,
  calculateDetectionCostLedger,
  catalogFixtureCoverage,
} from './catalog.js';

const metadata = {
  name: 'Red overshirt',
  category: 'jacket' as const,
  colors: ['red'],
  notes: null,
};

test('uses strict Responses output and clamps detection boxes', async () => {
  const originalFetch = globalThis.fetch;
  let requestBody: Record<string, unknown> | undefined;
  globalThis.fetch = async (_input, init) => {
    requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return Response.json({
      id: 'resp_fixture',
      status: 'completed',
      service_tier: 'default',
      usage: {
        input_tokens: 2_500,
        input_tokens_details: { cached_tokens: 100, cache_write_tokens: 200 },
        output_tokens: 120,
        output_tokens_details: { reasoning_tokens: 0 },
      },
      output: [
        {
          content: [
            {
              type: 'output_text',
              text: JSON.stringify({
                detections: [
                  {
                    name: 'Red overshirt',
                    category: 'jacket',
                    colors: ['red'],
                    boundingBox: { top: 10, left: 900, bottom: 410, right: 1000 },
                  },
                ],
              }),
            },
          ],
        },
      ],
    });
  };
  try {
    const jpegBytes = await sharp({
      create: { width: 2400, height: 3200, channels: 3, background: '#ffffff' },
    })
      .jpeg()
      .toBuffer();
    const result = await new OpenAICatalogProvider('test-key').detect({
      jpegBytes,
      model: 'gpt-5.6-luna',
    });
    assert.equal(result.requestId, 'resp_fixture');
    assert.deepEqual(result.detections[0]?.boundingBox, {
      x: 900,
      y: 10,
      width: 100,
      height: 400,
    });
    assert.deepEqual(result.usage, {
      inputTokens: 2_500,
      cachedInputTokens: 100,
      cacheWriteInputTokens: 200,
      outputTokens: 120,
      reasoningTokens: 0,
      serviceTier: 'default',
      raw: {
        input_tokens: 2_500,
        input_tokens_details: { cached_tokens: 100, cache_write_tokens: 200 },
        output_tokens: 120,
        output_tokens_details: { reasoning_tokens: 0 },
      },
    });
    const format = (requestBody?.text as { format: { strict: boolean; schema: unknown } }).format;
    assert.equal(format.strict, true);
    assert.equal((format.schema as { additionalProperties: boolean }).additionalProperties, false);
    assert.deepEqual(requestBody?.reasoning, { effort: 'none' });
    assert.equal(requestBody?.max_output_tokens, 3_000);
    const prompt = (
      requestBody?.input as Array<{
        content: Array<{ type: string; text?: string }>;
      }>
    )[0]?.content.find(({ type }) => type === 'input_text')?.text;
    assert.match(
      prompt ?? '',
      /Treat screenshots and product grids as multiple pictured instances/,
    );
    assert.match(prompt ?? '', /exclude captions, controls, cards, background, and other garments/);
    assert.match(prompt ?? '', /Include the brand and product model.*clearly identifiable/);
    assert.match(prompt ?? '', /Nike Air Max 95/);
    assert.match(prompt ?? '', /Do not guess them when uncertain/);
    assert.match(prompt ?? '', /normalized integer coordinates/);
    const imageInput = (
      requestBody?.input as Array<{
        content: Array<{ type: string; image_url?: string }>;
      }>
    )[0]?.content.find(({ type }) => type === 'input_image')?.image_url;
    const prepared = Buffer.from(imageInput?.split(',')[1] ?? '', 'base64');
    const preparedMetadata = await sharp(prepared).metadata();
    assert.equal(preparedMetadata.width, 1200);
    assert.equal(preparedMetadata.height, 1600);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('requires the detection usage ledger', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => Response.json({
    id: 'missing-usage',
    status: 'completed',
    output: [{ content: [{ type: 'output_text', text: '{"detections":[]}' }] }],
  });
  try {
    const jpegBytes = await sharp({
      create: { width: 100, height: 100, channels: 3, background: '#fff' },
    }).jpeg().toBuffer();
    await assert.rejects(
      new OpenAICatalogProvider('test-key').detect({ jpegBytes, model: 'gpt-5.6-luna' }),
      (error: unknown) => error instanceof CatalogProviderError && error.category === 'accounting',
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('sends one requested quality and requires the provider usage ledger', async () => {
  const originalFetch = globalThis.fetch;
  let form: FormData | undefined;
  globalThis.fetch = async (_input, init) => {
    form = init?.body as FormData;
    return Response.json({
      id: 'image_fixture',
      service_tier: 'default',
      data: [{ b64_json: Buffer.from('png fixture').toString('base64') }],
      usage: {
        input_tokens: 13,
        input_tokens_details: { text_tokens: 5, image_tokens: 8 },
        output_tokens: 21,
      },
    });
  };
  try {
    const result = await new OpenAICatalogProvider('test-key').generate({
      referenceJpeg: Buffer.from('jpeg fixture'),
      metadata,
      model: 'gpt-image-2',
      quality: 'low',
      size: '816x816',
      promptVersion: shelfImagePromptVersion,
    });
    assert.equal(form?.get('quality'), 'low');
    assert.equal(form?.get('size'), '816x816');
    assert.equal(form?.get('output_format'), 'png');
    assert.deepEqual(
      {
        text: result.usage.textInputTokens,
        image: result.usage.imageInputTokens,
        output: result.usage.outputTokens,
      },
      { text: 5, image: 8, output: 21 },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }

  globalThis.fetch = async () =>
    Response.json({
      data: [{ b64_json: Buffer.from('x').toString('base64') }],
    });
  try {
    await assert.rejects(
      new OpenAICatalogProvider('test-key').generate({
        referenceJpeg: Buffer.from('jpeg fixture'),
        metadata,
        model: 'gpt-image-2',
        quality: 'high',
        size: '816x816',
        promptVersion: shelfImagePromptVersion,
      }),
      (error: unknown) => error instanceof CatalogProviderError && error.category === 'accounting',
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('sends the source and earlier Shelf Image with upgrade feedback', async () => {
  const originalFetch = globalThis.fetch;
  let form: FormData | undefined;
  globalThis.fetch = async (_input, init) => {
    form = init?.body as FormData;
    return Response.json({
      id: 'upgrade_fixture',
      service_tier: 'default',
      data: [{ b64_json: Buffer.from('png fixture').toString('base64') }],
      usage: {
        input_tokens: 13,
        input_tokens_details: { text_tokens: 5, image_tokens: 8 },
        output_tokens: 21,
      },
    });
  };
  try {
    const source = Buffer.from([0xff, 0xd8, 0xff, 0xe0]);
    const earlier = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    await new OpenAICatalogProvider('test-key').generate({
      referenceJpeg: source,
      previousShelfImage: earlier,
      feedback: 'Farbe stimmt nicht',
      metadata,
      model: 'gpt-image-2',
      quality: 'high',
      size: '816x816',
      promptVersion: shelfImagePromptVersion,
    });

    const references = form?.getAll('image[]') as File[];
    assert.deepEqual(references.map((file) => file.name), [
      'reference.jpg',
      'previous-shelf-image.png',
    ]);
    assert.match(String(form?.get('prompt')), /Farbe stimmt nicht/);
    assert.match(String(form?.get('prompt')), /original source.*ground truth/i);
    assert.match(String(form?.get('prompt')), /must not be copied unchanged/i);
    assert.match(String(form?.get('prompt')), /visibly correct it/i);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('orders identity before garments and sends custom inspiration dimensions', async () => {
  const originalFetch = globalThis.fetch;
  let form: FormData | undefined;
  globalThis.fetch = async (_input, init) => {
    form = init?.body as FormData;
    return Response.json({
      id: 'look_fixture',
      data: [{ b64_json: Buffer.from('png fixture').toString('base64') }],
      usage: {
        input_tokens_details: { text_tokens: 3, image_tokens: 20 },
        output_tokens: 40,
      },
    });
  };
  try {
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0]);
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const webp = Buffer.from('RIFF0000WEBP');
    await new OpenAICatalogProvider('test-key').generateComposite({
      references: [jpeg, png, webp],
      prompt: 'candid look',
      model: 'gpt-image-2.5-flare',
      quality: 'medium',
      size: '1024x1280',
    });
    assert.equal(form?.get('quality'), 'medium');
    assert.equal(form?.get('size'), '1024x1280');
    const references = form?.getAll('image[]') as File[];
    assert.deepEqual(
      references.map((file) => file.name),
      ['reference-1.jpg', 'reference-2.png', 'reference-3.webp'],
    );
    assert.deepEqual(
      references.map((file) => file.type),
      ['image/jpeg', 'image/png', 'image/webp'],
    );
    assert.deepEqual(Buffer.from(await references[0]!.arrayBuffer()), jpeg);
    await new OpenAICatalogProvider('test-key').generateComposite({
      references: [jpeg, png],
      prompt: 'compact look',
      model: 'gpt-image-2.5-flare',
      quality: 'low',
      size: '768x960',
    });
    assert.equal(form?.get('size'), '768x960');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('replay outputs are isolated and cost arithmetic stays integer', async () => {
  const replay = new ReplayCatalogProvider([
    {
      key: 'generate:gpt-image-2.5-flare:medium',
      generation: {
        requestId: 'replay-medium',
        pngBytes: Buffer.from([1, 2, 3]),
        usage: {
          textInputTokens: 10,
          imageInputTokens: 20,
          outputTokens: 30,
          serviceTier: 'default',
          raw: {},
        },
      },
    },
  ]);
  const first = await replay.generate({
    model: 'gpt-image-2.5-flare',
    quality: 'medium',
  });
  first.pngBytes[0] = 9;
  const second = await replay.generate({
    model: 'gpt-image-2.5-flare',
    quality: 'medium',
  });
  assert.equal(second.pngBytes[0], 1);
  assert.equal(
    calculateCostMicrounits(first.usage, {
      effectiveDate: '2026-08-03',
      textInputMicrodollarsPerMillion: 1_000_000,
      imageInputMicrodollarsPerMillion: 2_000_000,
      imageOutputMicrodollarsPerMillion: 3_000_000,
    }),
    140,
  );
  assert.ok(catalogFixtureCoverage.includes('missing-usage-ledger'));
  assert.ok(catalogFixtureCoverage.includes('high-quality'));
});

test('prices each detection token class at its captured rate', () => {
  assert.deepEqual(
    calculateDetectionCostLedger(
      {
        inputTokens: 100,
        cachedInputTokens: 10,
        cacheWriteInputTokens: 20,
        outputTokens: 50,
      },
      {
        model: 'gpt-5.6-luna',
        effectiveDate: '2026-07-30',
        inputMicrodollarsPerMillion: 200_000,
        cachedInputMicrodollarsPerMillion: 20_000,
        cacheWriteInputMicrodollarsPerMillion: 250_000,
        outputMicrodollarsPerMillion: 1_200_000,
      },
    ),
    {
      inputMicrounits: 14,
      cachedInputMicrounits: 1,
      cacheWriteInputMicrounits: 5,
      outputMicrounits: 60,
      totalMicrounits: 80,
    },
  );
});

test('classifies transient and non-retryable provider failures', async () => {
  const originalFetch = globalThis.fetch;
  const jpegBytes = await sharp({
    create: { width: 10, height: 10, channels: 3, background: '#ffffff' },
  })
    .jpeg()
    .toBuffer();
  globalThis.fetch = async () =>
    Response.json(
      { error: { code: 'rate_limit_exceeded', message: 'slow down' } },
      { status: 429 },
    );
  try {
    await assert.rejects(
      new OpenAICatalogProvider('test-key').detect({
        jpegBytes,
        model: 'gpt-5.6-luna',
      }),
      (error: unknown) =>
        error instanceof CatalogProviderError && error.category === 'rate-limit' && error.retryable,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }

  globalThis.fetch = async () =>
    Response.json(
      { error: { code: 'content_policy_violation', message: 'blocked' } },
      { status: 400 },
    );
  try {
    await assert.rejects(
      new OpenAICatalogProvider('test-key').detect({
        jpegBytes,
        model: 'gpt-5.6-luna',
      }),
      (error: unknown) =>
        error instanceof CatalogProviderError &&
        error.category === 'moderation' &&
        !error.retryable,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('look planning includes the occasion while keeping exact items mandatory', async () => {
  const originalFetch = globalThis.fetch;
  let prompt = '';
  globalThis.fetch = async (_input, init) => {
    prompt = JSON.parse(String(init?.body)).input;
    return Response.json({
      id: 'plan-party',
      output_text: JSON.stringify({
        itemIds: ['chosen', 'complement'],
        concept: { activity: 'dancing', scene: 'a party', framing: 'full-body', mood: 'festive' },
      }),
    });
  };
  try {
    const provider = new OpenAICatalogProvider('fixture-key');
    const result = await provider.planLook({
      candidates: [{ id: 'chosen', metadata }, { id: 'complement', metadata }],
      recent: [], exactItemIds: ['chosen'], categories: [], occasion: 'party', model: 'fixture',
    });
    assert.match(prompt, /Occasion: "party"/);
    assert.match(prompt, /Exact: \["chosen"\]/);
    assert.deepEqual(result.itemIds, ['chosen', 'complement']);
    // Dropping a mandated item is a bad sample, not a permanent failure.
    await assert.rejects(provider.planLook({
      candidates: [{ id: 'chosen', metadata }, { id: 'complement', metadata }, { id: 'missing', metadata }],
      recent: [], exactItemIds: ['missing'], categories: [], occasion: 'business', model: 'fixture',
    }), (error) =>
      error instanceof CatalogProviderError &&
      error.retryable &&
      /1 mandated item\(s\) missing/.test(error.message));
  } finally {
    globalThis.fetch = originalFetch;
  }
});
