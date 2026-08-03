import { databaseConfigSchema, objectStorageConfigSchema } from '@form/service';
import { z } from 'zod';

export const workerConfigSchema = z.object({
  ...databaseConfigSchema.shape,
  ...objectStorageConfigSchema.shape,
  OPENAI_API_KEY: z.string().min(1),
  REMOTE_IMAGE_GLOBAL_CONCURRENCY: z.coerce.number().int().positive().default(2),
  REMOTE_IMAGE_ACCOUNT_CONCURRENCY: z.coerce.number().int().positive().default(1),
  REMOTE_IMAGE_LEASE_SECONDS: z.coerce.number().int().positive().default(60),
  REMOTE_IMAGE_POLL_INTERVAL_MS: z.coerce.number().int().min(250).default(1_000),
});

export type WorkerConfig = z.infer<typeof workerConfigSchema>;

export function readWorkerConfig(
  environment: NodeJS.ProcessEnv = process.env,
): WorkerConfig {
  return workerConfigSchema.parse(environment);
}
