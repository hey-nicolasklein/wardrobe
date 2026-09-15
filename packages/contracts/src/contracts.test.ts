import assert from 'node:assert/strict';
import test from 'node:test';

import {
  apiErrorSchema,
  accountCredentialsSchema,
  createWardrobeItemRequestSchema,
  createCharacterSheetRequestSchema,
  createLookRequestSchema,
  detectionProposalsResponseSchema,
  enqueueGenerationRequestSchema,
  garmentDetectionSchema,
  refineCharacterSheetRequestSchema,
  signInRequestSchema,
  updateWardrobeItemRequestSchema,
  wardrobeItemDetailResponseSchema,
} from './index.js';

const id = 'opaque-id-0123456789abcdef';

test('accepts a normalized detection inside the source frame', () => {
  const result = garmentDetectionSchema.safeParse({
    id,
    name: 'Navy overshirt',
    category: 'jacket',
    colors: ['navy'],
    boundingBox: { x: 120, y: 80, width: 700, height: 850 },
  });

  assert.equal(result.success, true);
});

test('reports durable detection progress beside proposals', () => {
  const result = detectionProposalsResponseSchema.safeParse({
    detections: [],
    attempt: {
      id,
      sourcePhotoId: id,
      state: 'processing',
      model: 'gpt-5.4-mini',
      failureCategory: null,
      createdAt: '2026-08-05T08:00:00.000Z',
      finishedAt: null,
    },
  });
  assert.equal(result.success, true);
});

test('rejects a normalized detection extending beyond the source frame', () => {
  const result = garmentDetectionSchema.safeParse({
    id,
    name: 'Navy overshirt',
    category: 'jacket',
    colors: ['navy'],
    boundingBox: { x: 900, y: 80, width: 200, height: 850 },
  });

  assert.equal(result.success, false);
});

test('defaults paid generation to low quality at 816 square', () => {
  const request = enqueueGenerationRequestSchema.parse({
    wardrobeItemId: id,
    idempotencyKey: 'command-0123456789abcdef',
  });

  assert.equal(request.quality, 'low');
  assert.equal(request.size, '816x816');
  assert.equal(request.autoKeep, true);
  assert.equal(request.feedback, null);
  assert.equal(
    enqueueGenerationRequestSchema.parse({
      wardrobeItemId: id,
      autoKeep: true,
      idempotencyKey: 'automatic-command-0123456789',
    }).autoKeep,
    true,
  );
});

test('accepts feedback for a Shelf Image upgrade', () => {
  const request = enqueueGenerationRequestSchema.parse({
    wardrobeItemId: id,
    feedback: 'Proportionen stimmen nicht. Details fehlen.',
    idempotencyKey: 'upgrade-command-0123456789',
  });
  assert.equal(request.feedback, 'Proportionen stimmen nicht. Details fehlen.');
});

test('requires an offline-safe edit command to change at least one field', () => {
  const result = updateWardrobeItemRequestSchema.safeParse({
    expectedRecordVersion: 2,
    idempotencyKey: 'command-0123456789abcdef',
  });

  assert.equal(result.success, false);
});

test('keeps error categories actionable and payloads strict', () => {
  const result = apiErrorSchema.safeParse({
    category: 'conflict',
    code: 'stale-record-version',
    message: 'The item changed on another device.',
    retryable: false,
    unexpected: true,
  });

  assert.equal(result.success, false);
});

test('makes the browser cookie and native token transports explicit', () => {
  assert.equal(
    signInRequestSchema.safeParse({
      email: 'owner@example.test',
      password: 'secret',
      transport: 'cookie',
    }).success,
    true,
  );
  assert.equal(
    signInRequestSchema.safeParse({
      email: 'owner@example.test',
      password: 'secret',
    }).success,
    false,
  );
});

test('shares administrator and sign-in credential limits', () => {
  assert.equal(
    accountCredentialsSchema.safeParse({
      email: 'not-an-email',
      password: 'long-enough-password',
    }).success,
    false,
  );
  assert.equal(
    accountCredentialsSchema.safeParse({
      email: 'owner@example.test',
      password: 'x'.repeat(257),
    }).success,
    false,
  );
});

test('does not create an already archived Wardrobe Item from a detection', () => {
  const result = createWardrobeItemRequestSchema.safeParse({
    detectionProposalId: id,
    state: 'archived',
    idempotencyKey: 'command-0123456789abcdef',
  });

  assert.equal(result.success, false);
});

test('requires immutable generation history in item detail responses', () => {
  const result = wardrobeItemDetailResponseSchema.safeParse({
    wardrobeItem: {},
    sourcePhoto: {},
    shelfImageVersions: [],
  });

  assert.equal(result.success, false);
});

test('keeps Character Sheet and Look creation constrained and strict', () => {
  assert.equal(
    createCharacterSheetRequestSchema.safeParse({
      referenceAssetIds: [id],
      note: null,
      idempotencyKey: 'character-command-0123456789',
    }).success,
    true,
  );
  assert.equal(
    createCharacterSheetRequestSchema.safeParse({
      referenceAssetIds: [id, id],
      idempotencyKey: 'character-command-0123456789',
    }).success,
    false,
  );
  assert.equal(
    refineCharacterSheetRequestSchema.safeParse({
      referenceAssetIds: [id],
      instruction: 'Fix the back view',
      idempotencyKey: 'character-command-0123456789',
    }).success,
    true,
  );
  // The parent sheet occupies the fourth reference slot, and a refinement needs a target.
  assert.equal(
    refineCharacterSheetRequestSchema.safeParse({
      referenceAssetIds: [id, id, id, id],
      instruction: 'Fix the back view',
      idempotencyKey: 'character-command-0123456789',
    }).success,
    false,
  );
  assert.equal(
    refineCharacterSheetRequestSchema.safeParse({
      referenceAssetIds: [id],
      instruction: '  ',
      idempotencyKey: 'character-command-0123456789',
    }).success,
    false,
  );
  assert.deepEqual(
    createLookRequestSchema.parse({
      idempotencyKey: 'look-command-0123456789',
    }),
    {
      exactItemIds: [],
      categories: [],
      parentLookId: null,
      quality: 'low',
      preserveComposition: false,
      completeWithWardrobe: true,
      idempotencyKey: 'look-command-0123456789',
    },
  );
  assert.equal(
    createLookRequestSchema.parse({
      completeWithWardrobe: false,
      idempotencyKey: 'look-command-0123456789',
    }).completeWithWardrobe,
    false,
  );
  assert.equal(
    createLookRequestSchema.safeParse({
      idempotencyKey: 'look-command-0123456789',
      freeTextPrompt: 'invent something',
    }).success,
    false,
  );
});


test('look occasions accept supported choices and reject unknown ones', () => {
  for (const occasion of ['night-out', 'party', 'business', 'casual', null]) {
    assert.equal(createLookRequestSchema.parse({
      idempotencyKey: 'look-command-0123456789', occasion,
    }).occasion, occasion);
  }
  assert.equal(createLookRequestSchema.safeParse({
    idempotencyKey: 'look-command-0123456789', occasion: 'unknown',
  }).success, false);
});
