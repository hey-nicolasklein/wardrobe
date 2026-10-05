import { z } from 'zod';

import {
  detectionProposalSchema,
  detectionAttemptSchema,
  generationAttemptSchema,
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
  characterSheetSchema,
  lookOccasionSchema,
  lookSchema,
  lookStyleSchema,
  lookCompletionSchema,
  generationCostSummarySchema,
  supportedCategorySchema,
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
    code: z
      .string()
      .regex(/^[a-z0-9-]+$/)
      .max(80),
    message: z.string().min(1).max(500),
    retryable: z.boolean(),
    fieldErrors: z.record(z.string(), z.array(z.string())).optional(),
    requestId: z.string().min(1).max(128).optional(),
  })
  .strict();

export const errorResponseSchema = z.object({ error: apiErrorSchema }).strict();

export const accountCredentialsSchema = z
  .object({
    email: z.email(),
    password: z.string().min(1).max(256),
  })
  .strict();

export const signInRequestSchema = accountCredentialsSchema
  .extend({ transport: z.enum(['cookie', 'token']) })
  .strict();

export const identitySignInRequestSchema = z
  .object({
    idToken: z.string().min(1).max(8192),
    transport: z.enum(['cookie', 'token']),
  })
  .strict();

// Only served when the API runs with DEV_SIGN_IN=true.
export const devSignInRequestSchema = z
  .object({
    email: z.email(),
    transport: z.enum(['cookie', 'token']),
  })
  .strict();

export const creditsResponseSchema = z
  .object({ metered: z.boolean(), balance: z.number().int() })
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
export const currentSessionResponseSchema = z.object({ session: sessionSchema }).strict();

export const createUploadIntentRequestSchema = z
  .object({
    fileName: z.string().trim().min(1).max(255),
    contentType: z.enum(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']),
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

export const createDownloadUrlResponseSchema = z
  .object({
    assetId: opaqueIdSchema,
    downloadUrl: z.url(),
    expiresAt: z.iso.datetime({ offset: true }),
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
      metadata !== undefined || state !== undefined || currentShelfImageVersionId !== undefined,
    { message: 'At least one editable field is required' },
  );

export const wardrobeItemResponseSchema = z.object({ wardrobeItem: wardrobeItemSchema }).strict();

export const wardrobeItemsResponseSchema = z
  .object({ wardrobeItems: z.array(wardrobeItemSchema) })
  .strict();

export const wardrobeItemDetailResponseSchema = z
  .object({
    wardrobeItem: wardrobeItemSchema,
    sourcePhoto: sourcePhotoSchema,
    shelfImageVersions: z.array(shelfImageVersionSchema),
    generationAttempts: z.array(generationAttemptSchema),
  })
  .strict();

export const detectionProposalsResponseSchema = z
  .object({
    detections: z.array(detectionProposalSchema),
    attempt: detectionAttemptSchema.nullable(),
  })
  .strict();

export const enqueueDetectionRequestSchema = z
  .object({ idempotencyKey: idempotencyKeySchema })
  .strict();

export const enqueueDetectionResponseSchema = z
  .object({ jobId: opaqueIdSchema, detectionAttemptId: opaqueIdSchema })
  .strict();

export const createWardrobeItemRequestSchema = z
  .object({
    detectionProposalId: opaqueIdSchema,
    state: itemStateSchema.exclude(['archived']),
    metadata: itemMetadataSchema.optional(),
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();

export const enqueueGenerationRequestSchema = z
  .object({
    wardrobeItemId: opaqueIdSchema,
    quality: generationQualitySchema.default('low'),
    size: generationSizeSchema.default('816x816'),
    // When true the completed image is adopted as the Wardrobe Item's current
    // Shelf Image without a keep/reject review step.
    autoKeep: z.boolean().default(true),
    feedback: z.string().trim().min(1).max(1_000).nullable().default(null),
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

export const rejectShelfImageRequestSchema = z
  .object({
    generationAttemptId: opaqueIdSchema,
    expectedRecordVersion: recordVersionSchema,
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();

export const restoreShelfImageVersionRequestSchema = z
  .object({
    expectedRecordVersion: recordVersionSchema,
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();

export const permanentlyDeleteWardrobeItemRequestSchema = z
  .object({
    expectedRecordVersion: recordVersionSchema,
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();

export const permanentlyDeleteWardrobeItemResponseSchema = z
  .object({
    wardrobeItemId: opaqueIdSchema,
    sourcePhotoDeleted: z.boolean(),
    deletedAssetIds: z.array(opaqueIdSchema),
  })
  .strict();

export const createCharacterSheetRequestSchema = z
  .object({
    // The client has already composed and uploaded the finished photo collage.
    referenceAssetIds: z.array(opaqueIdSchema).length(1),
    note: z.string().trim().max(1_000).nullable().default(null),
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();
export const activateCharacterSheetRequestSchema = z
  .object({
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();
export const characterSheetsResponseSchema = z
  .object({
    characterSheets: z.array(characterSheetSchema),
  })
  .strict();
export const characterSheetResponseSchema = z
  .object({ characterSheet: characterSheetSchema })
  .strict();

export const createLookRequestSchema = z
  .object({
    exactItemIds: z.array(opaqueIdSchema).max(12).default([]),
    categories: z.array(supportedCategorySchema).max(9).default([]),
    occasion: lookOccasionSchema.nullable().optional(),
    style: lookStyleSchema.default('candid'),
    parentLookId: opaqueIdSchema.nullable().default(null),
    quality: generationQualitySchema.default('low'),
    preserveComposition: z.boolean().default(false),
    completeWithWardrobe: z.boolean().default(true),
    // Supersedes completeWithWardrobe when present. The PWA still sends the boolean.
    completion: lookCompletionSchema.optional(),
    // A try-on: dress this uploaded source photo in exactItemIds 1:1 instead of
    // generating a new scene. Occasion, style, and completion do not apply.
    baseAssetId: opaqueIdSchema.optional(),
    // With parentLookId: the same outfit and scene, shot from a different angle.
    reshoot: z.boolean().optional(),
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();
// Plans `count` outfits without rendering them; the user picks which to render.
export const proposeLooksRequestSchema = z
  .object({
    exactItemIds: z.array(opaqueIdSchema).max(12).default([]),
    categories: z.array(supportedCategorySchema).max(9).default([]),
    occasion: lookOccasionSchema.nullable().optional(),
    style: lookStyleSchema.default('candid'),
    completion: lookCompletionSchema.default('wardrobe'),
    count: z.number().int().min(1).max(4).default(3),
    // Pieces the user ruled out while swiping. Never planned into an outfit.
    excludedItemIds: z.array(opaqueIdSchema).max(200).default([]),
    // Adds to the open proposals instead of replacing them.
    append: z.boolean().default(false),
    // With append: open proposals planned with outdated choices, dropped now.
    discardLookIds: z.array(opaqueIdSchema).max(20).default([]),
    idempotencyKey: idempotencyKeySchema,
  })
  .strict();
// Swipe marks applied to the open proposals in place, without re-planning.
export const adjustLookProposalsRequestSchema = z
  .object({
    keepItemIds: z.array(opaqueIdSchema).max(20).default([]),
    excludeItemIds: z.array(opaqueIdSchema).max(200).default([]),
  })
  .strict();
export const renderLookProposalRequestSchema = z
  .object({ quality: generationQualitySchema.default('low'), idempotencyKey: idempotencyKeySchema })
  .strict();
export const proposeLooksResponseSchema = z.object({ lookIds: z.array(opaqueIdSchema) }).strict();
export const lookShotPreferencesResponseSchema = z
  .object({ hiddenShots: z.array(z.string().min(1).max(40)) })
  .strict();
export const setLookShotPreferenceRequestSchema = z.object({ hidden: z.boolean() }).strict();
export const setLookLikedRequestSchema = z.object({ liked: z.boolean() }).strict();
// Photos of the user for try-ons, see `try_on_photos`.
export const addTryOnPhotoRequestSchema = z.object({ assetId: opaqueIdSchema }).strict();
export const tryOnPhotosResponseSchema = z
  .object({
    photos: z.array(z.object({ assetId: opaqueIdSchema, createdAt: z.string().datetime() }).strict()),
  })
  .strict();
// Why the feed picks the shots it picks: per shot the hearts, whether it was
// used recently or hidden, and the resulting weight and chance within its style.
export const lookShotWeightsResponseSchema = z
  .object({
    shots: z.array(
      z
        .object({
          style: lookStyleSchema,
          shot: z.string().min(1).max(40),
          likes: z.number().int().nonnegative(),
          recent: z.boolean(),
          hidden: z.boolean(),
          weight: z.number().nonnegative(),
          chance: z.number().min(0).max(1),
        })
        .strict(),
    ),
  })
  .strict();
export const retryLookRequestSchema = z.object({ idempotencyKey: idempotencyKeySchema }).strict();
export const looksResponseSchema = z.object({ looks: z.array(lookSchema) }).strict();
export const lookResponseSchema = z.object({ look: lookSchema }).strict();
export const generationCostSummaryResponseSchema = z
  .object({ costs: generationCostSummarySchema })
  .strict();

export const personalResetRequestSchema = z
  .object({
    confirmation: z.enum(['ALLES LÖSCHEN', 'DELETE EVERYTHING']),
  })
  .strict();

export type ApiErrorCategory = z.infer<typeof apiErrorCategorySchema>;
export type ApiError = z.infer<typeof apiErrorSchema>;
export type SignInRequest = z.infer<typeof signInRequestSchema>;
export type SignInResponse = z.infer<typeof signInResponseSchema>;
export type IdentitySignInRequest = z.infer<typeof identitySignInRequestSchema>;
export type DevSignInRequest = z.infer<typeof devSignInRequestSchema>;
export type CreditsResponse = z.infer<typeof creditsResponseSchema>;
export type WardrobeItemResponse = z.infer<typeof wardrobeItemResponseSchema>;
export type WardrobeItemsResponse = z.infer<typeof wardrobeItemsResponseSchema>;
export type WardrobeItemDetailResponse = z.infer<typeof wardrobeItemDetailResponseSchema>;
export type CreateDownloadUrlResponse = z.infer<typeof createDownloadUrlResponseSchema>;
export type UpdateWardrobeItemRequest = z.infer<typeof updateWardrobeItemRequestSchema>;
export type RejectShelfImageRequest = z.infer<typeof rejectShelfImageRequestSchema>;
export type RestoreShelfImageVersionRequest = z.infer<typeof restoreShelfImageVersionRequestSchema>;
export type DetectionProposalsResponse = z.infer<typeof detectionProposalsResponseSchema>;
export type CreateUploadIntentRequest = z.infer<typeof createUploadIntentRequestSchema>;
export type CreateUploadIntentResponse = z.infer<typeof createUploadIntentResponseSchema>;
export type CompleteSourceUploadResponse = z.infer<typeof completeSourceUploadResponseSchema>;
export type CreateWardrobeItemRequest = z.infer<typeof createWardrobeItemRequestSchema>;
