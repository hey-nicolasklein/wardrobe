import assert from 'node:assert/strict';
import test from 'node:test';

import {
  CatalogProviderError,
  OpenAICatalogProvider,
  ReplayCatalogProvider,
  shelfImagePromptVersion,
} from './catalog-provider.js';
import { calculateCostMicrounits, catalogFixtureCoverage } from './catalog.js';

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
                    boundingBox: { x: 900, y: 10, width: 300, height: 400 },
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
    const result = await new OpenAICatalogProvider('test-key').detect({
      jpegBytes: Buffer.from('fixture'),
      model: 'gpt-5.4-mini',
    });
    assert.equal(result.requestId, 'resp_fixture');
    assert.deepEqual(result.detections[0]?.boundingBox, {
      x: 900,
      y: 10,
      width: 100,
      height: 400,
    });
    const format = (requestBody?.text as { format: { strict: boolean; schema: unknown } }).format;
    assert.equal(format.strict, true);
    assert.equal((format.schema as { additionalProperties: boolean }).additionalProperties, false);
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
    Response.json({ data: [{ b64_json: Buffer.from('x').toString('base64') }] });
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
      (error: unknown) =>
        error instanceof CatalogProviderError && error.category === 'accounting',
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('replay outputs are isolated and cost arithmetic stays integer', async () => {
  const replay = new ReplayCatalogProvider([
    {
      key: 'generate:gpt-image-2:medium',
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
  const first = await replay.generate({ model: 'gpt-image-2', quality: 'medium' });
  first.pngBytes[0] = 9;
  const second = await replay.generate({ model: 'gpt-image-2', quality: 'medium' });
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

test('classifies transient and non-retryable provider failures', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () =>
    Response.json({ error: { code: 'rate_limit_exceeded', message: 'slow down' } }, { status: 429 });
  try {
    await assert.rejects(
      new OpenAICatalogProvider('test-key').detect({
        jpegBytes: Buffer.from('fixture'),
        model: 'gpt-5.4-mini',
      }),
      (error: unknown) =>
        error instanceof CatalogProviderError &&
        error.category === 'rate-limit' &&
        error.retryable,
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
        jpegBytes: Buffer.from('fixture'),
        model: 'gpt-5.4-mini',
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
