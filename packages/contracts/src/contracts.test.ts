import assert from 'node:assert/strict';
import test from 'node:test';

import {
  apiErrorSchema,
  enqueueGenerationRequestSchema,
  garmentDetectionSchema,
  updateWardrobeItemRequestSchema,
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

test('defaults paid generation to the agreed low 816 square contract', () => {
  const request = enqueueGenerationRequestSchema.parse({
    wardrobeItemId: id,
    idempotencyKey: 'command-0123456789abcdef',
  });

  assert.equal(request.quality, 'low');
  assert.equal(request.size, '816x816');
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
