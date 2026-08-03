import { z } from 'zod';

import {
  generationQualitySchema,
  generationSizeSchema,
  itemMetadataSchema,
  itemStateSchema,
  opaqueIdSchema,
  privateAssetSchema,
  recordVersionSchema,
  shelfImageVersionSchema,
  sourcePhotoSchema,
  wardrobeItemSchema,
} from './domain.js';

export const idempotencyKeySchema = z.string().min(16).max(128);

export const apiErrorCategorySchema = z.enum([
  'validation',
  'offline',
  'authentication',
  'authorization',
  'not-found',
  'conflict',
  'transient-provider',
  'moderation',
  'capacity',
  'internal',
]);

export const apiErrorSchema = z
  .object({
    category: apiErrorCategorySchema,
    code: z.string().regex(/^[a-z0-9-]+$/).max(80),
    message: z.string().min(1).max(500),
    retryable: z.boolean(),
    fieldErrors: z.record(z.string(), z.array(z.string())).optional(),
    requestId: z.string().min(1).max(128).optional(),
  })
  .strict();

export const errorResponseSchema = z.object({ error: apiErrorSchema }).strict();

export const signInRequestSchema = z
  .object({
    email: z.email(),
    password: z.string().min(1).max(256),
  })
  .strict();

export const sessionSchema = z
  .object({
    accountId: opaqueIdSchema,
    email: z.email(),
    expiresAt: z.iso.datetime({ offset: true }),
    nativeToken: z.string().min(32).nullable(),
  })
  .strict();

export const signInResponseSchema = z.object({ session: sessionSchema }).strict();

export const createUploadIntentRequestSchema = z
  .object({
    fileName: z.string().trim().min(1).max(255),
    contentType: z.enum(['image/jpeg', 'image/png', 'image/heic', 'image/heif']),
    byteSize: z.number().int().positive(),
  })
  .strict();

export const createUploadIntentResponseSchema = z
  .object({
    assetId: opaqueIdSchema,
    uploadUrl: z.url(),
    expiresAt: z.iso.datetime({ offset: true }),
    headers: z.record(z.string(), z.string()),
  })
  .strict();

export const completeSourceUploadRequestSchema = z
  .object({
    assetId: opaqueIdSchema,
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();

export const completeSourceUploadResponseSchema = z
  .object({
    sourcePhoto: sourcePhotoSchema,
    asset: privateAssetSchema,
  })
  .strict();

export const updateWardrobeItemRequestSchema = z
  .object({
    metadata: itemMetadataSchema.optional(),
    state: itemStateSchema.optional(),
    currentShelfImageVersionId: opaqueIdSchema.nullable().optional(),
    expectedRecordVersion: recordVersionSchema,
    idempotencyKey: idempotencyKeySchema,
  })
  .strict()
  .refine(
    ({ metadata, state, currentShelfImageVersionId }) =>
      metadata !== undefined ||
      state !== undefined ||
      currentShelfImageVersionId !== undefined,
    { message: 'At least one editable field is required' },
  );

export const wardrobeItemResponseSchema = z
  .object({ wardrobeItem: wardrobeItemSchema })
  .strict();

export const enqueueGenerationRequestSchema = z
  .object({
    wardrobeItemId: opaqueIdSchema,
    quality: generationQualitySchema.default('low'),
    size: generationSizeSchema.default('816x816'),
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();

export const enqueueGenerationResponseSchema = z
  .object({ jobId: opaqueIdSchema, generationAttemptId: opaqueIdSchema })
  .strict();

export const keepShelfImageRequestSchema = z
  .object({
    generationAttemptId: opaqueIdSchema,
    expectedRecordVersion: recordVersionSchema,
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();

export const keepShelfImageResponseSchema = z
  .object({
    wardrobeItem: wardrobeItemSchema,
    shelfImageVersion: shelfImageVersionSchema,
  })
  .strict();

export type ApiErrorCategory = z.infer<typeof apiErrorCategorySchema>;
export type ApiError = z.infer<typeof apiErrorSchema>;
export type SignInRequest = z.infer<typeof signInRequestSchema>;
export type SignInResponse = z.infer<typeof signInResponseSchema>;
export type UpdateWardrobeItemRequest = z.infer<
  typeof updateWardrobeItemRequestSchema
>;
