import { z } from 'zod';

import {
  generationStateSchema,
  opaqueIdSchema,
  recordVersionSchema,
  timestampSchema,
  wardrobeItemSchema,
} from './domain.js';

const eventEnvelopeSchema = z.object({
  id: opaqueIdSchema,
  accountId: opaqueIdSchema,
  occurredAt: timestampSchema,
});

export const jobUpdatedEventSchema = eventEnvelopeSchema
  .extend({
    type: z.literal('remote-image-job.updated'),
    jobId: opaqueIdSchema,
    wardrobeItemId: opaqueIdSchema.nullable(),
    state: generationStateSchema,
  })
  .strict();

export const wardrobeItemUpdatedEventSchema = eventEnvelopeSchema
  .extend({
    type: z.literal('wardrobe-item.updated'),
    wardrobeItem: wardrobeItemSchema,
    recordVersion: recordVersionSchema,
  })
  .strict();

export const domainEventSchema = z.discriminatedUnion('type', [
  jobUpdatedEventSchema,
  wardrobeItemUpdatedEventSchema,
]);

export type JobUpdatedEvent = z.infer<typeof jobUpdatedEventSchema>;
export type WardrobeItemUpdatedEvent = z.infer<
  typeof wardrobeItemUpdatedEventSchema
>;
export type DomainEvent = z.infer<typeof domainEventSchema>;
