import { z } from 'zod';

export const opaqueIdSchema = z.string().min(16).max(128);
export const recordVersionSchema = z.number().int().nonnegative();
export const timestampSchema = z.iso.datetime({ offset: true });

export const itemStateSchema = z.enum(['wanting', 'owning', 'archived']);

export const itemStatusSchema = z.enum([
  'detecting',
  'reviewing-metadata',
  'queued',
  'generating',
  'needs-review',
  'ready',
  'failed',
]);

export const supportedCategorySchema = z.enum([
  'top',
  'jacket',
  'pants',
  'skirt',
  'dress',
  'shoes',
  'bag',
  'hat',
  'scarf',
]);

export const detectionCategorySchema = z.enum([
  ...supportedCategorySchema.options,
  'unsupported',
]);

export const itemNameSchema = z.string().trim().min(1).max(80);
export const colorSchema = z.string().trim().min(1).max(32);

export const itemMetadataSchema = z
  .object({
    name: itemNameSchema,
    category: supportedCategorySchema,
    colors: z.array(colorSchema).min(1).max(6),
    notes: z.string().trim().max(2_000).nullable(),
  })
  .strict();

export const normalizedBoundingBoxSchema = z
  .object({
    x: z.number().int().min(0).max(999),
    y: z.number().int().min(0).max(999),
    width: z.number().int().min(1).max(1_000),
    height: z.number().int().min(1).max(1_000),
  })
  .strict()
  .refine(({ x, width }) => x + width <= 1_000, {
    message: 'x + width must fit in the normalized 1000-unit frame',
    path: ['width'],
  })
  .refine(({ y, height }) => y + height <= 1_000, {
    message: 'y + height must fit in the normalized 1000-unit frame',
    path: ['height'],
  });

export const garmentDetectionSchema = z
  .object({
    id: opaqueIdSchema,
    name: itemNameSchema,
    category: detectionCategorySchema,
    colors: z.array(colorSchema).min(1).max(6),
    boundingBox: normalizedBoundingBoxSchema,
  })
  .strict();

export const detectionProposalSchema = garmentDetectionSchema
  .extend({
    sourcePhotoId: opaqueIdSchema,
    createdAt: timestampSchema,
  })
  .strict();

export const assetPurposeSchema = z.enum([
  'source-photo',
  'generation-reference',
  'shelf-image-keyed',
  'shelf-image-transparent',
  'fixture',
]);

export const privateAssetSchema = z
  .object({
    id: opaqueIdSchema,
    purpose: assetPurposeSchema,
    contentType: z.string().min(1).max(128),
    byteSize: z.number().int().nonnegative(),
    pixelWidth: z.number().int().positive().nullable(),
    pixelHeight: z.number().int().positive().nullable(),
    createdAt: timestampSchema,
  })
  .strict();

export const sourcePhotoSchema = z
  .object({
    id: opaqueIdSchema,
    assetId: opaqueIdSchema,
    createdAt: timestampSchema,
  })
  .strict();

export const generationQualitySchema = z.enum(['low', 'medium', 'high']);
export const generationSizeSchema = z.literal('816x816');
export const generationStateSchema = z.enum([
  'queued',
  'processing',
  'needs-review',
  'kept',
  'rejected',
  'failed',
]);

export const generationAttemptSchema = z
  .object({
    id: opaqueIdSchema,
    wardrobeItemId: opaqueIdSchema,
    sourcePhotoId: opaqueIdSchema,
    detectionProposalId: opaqueIdSchema.nullable(),
    state: generationStateSchema,
    reviewedMetadata: itemMetadataSchema,
    model: z.string().min(1).max(64),
    quality: generationQualitySchema,
    size: generationSizeSchema,
    promptVersion: z.string().min(1).max(64),
    keyedAssetId: opaqueIdSchema.nullable(),
    transparentAssetId: opaqueIdSchema.nullable(),
    providerRequestId: z.string().min(1).max(255).nullable(),
    costMicrounits: z.number().int().nonnegative().nullable(),
    usage: z
      .object({
        textInputTokens: z.number().int().nonnegative(),
        imageInputTokens: z.number().int().nonnegative(),
        outputTokens: z.number().int().nonnegative(),
        serviceTier: z.string().min(1).max(64),
      })
      .strict()
      .nullable(),
    costBreakdown: z
      .object({
        textInputMicrounits: z.number().int().nonnegative(),
        imageInputMicrounits: z.number().int().nonnegative(),
        imageOutputMicrounits: z.number().int().nonnegative(),
        totalMicrounits: z.number().int().nonnegative(),
        pricingEffectiveDate: z.iso.date(),
      })
      .strict()
      .nullable(),
    failureCategory: z.string().min(1).max(80).nullable(),
    createdAt: timestampSchema,
    finishedAt: timestampSchema.nullable(),
  })
  .strict();

export const shelfImageVersionSchema = z
  .object({
    id: opaqueIdSchema,
    wardrobeItemId: opaqueIdSchema,
    generationAttemptId: opaqueIdSchema,
    keyedAssetId: opaqueIdSchema,
    transparentAssetId: opaqueIdSchema,
    quality: generationQualitySchema,
    size: generationSizeSchema,
    promptVersion: z.string().min(1).max(64),
    keptAt: timestampSchema,
  })
  .strict();

export const wardrobeItemSchema = z
  .object({
    id: opaqueIdSchema,
    sourcePhotoId: opaqueIdSchema,
    state: itemStateSchema,
    status: itemStatusSchema,
    metadata: itemMetadataSchema,
    currentShelfImageVersionId: opaqueIdSchema.nullable(),
    recordVersion: recordVersionSchema,
    createdAt: timestampSchema,
    updatedAt: timestampSchema,
  })
  .strict();

export type ItemState = z.infer<typeof itemStateSchema>;
export type ItemStatus = z.infer<typeof itemStatusSchema>;
export type SupportedCategory = z.infer<typeof supportedCategorySchema>;
export type DetectionCategory = z.infer<typeof detectionCategorySchema>;
export type ItemMetadata = z.infer<typeof itemMetadataSchema>;
export type NormalizedBoundingBox = z.infer<typeof normalizedBoundingBoxSchema>;
export type GarmentDetection = z.infer<typeof garmentDetectionSchema>;
export type DetectionProposal = z.infer<typeof detectionProposalSchema>;
export type PrivateAsset = z.infer<typeof privateAssetSchema>;
export type SourcePhoto = z.infer<typeof sourcePhotoSchema>;
export type GenerationQuality = z.infer<typeof generationQualitySchema>;
export type GenerationAttempt = z.infer<typeof generationAttemptSchema>;
export type ShelfImageVersion = z.infer<typeof shelfImageVersionSchema>;
export type WardrobeItem = z.infer<typeof wardrobeItemSchema>;
