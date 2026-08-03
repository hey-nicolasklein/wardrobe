import { databaseConfigSchema, objectStorageConfigSchema } from '@form/service';
import { z } from 'zod';

export const workerConfigSchema = z.object({
  ...databaseConfigSchema.shape,
  ...objectStorageConfigSchema.shape,
  OPENAI_API_KEY: z.string().min(1),
  OPENAI_API_BASE_URL: z.url().default('https://api.openai.com/v1'),
  OPENAI_DETECTION_MODEL: z.string().min(1).default('gpt-5.4-mini'),
  OPENAI_PRICING_EFFECTIVE_DATE: z.iso.date(),
  OPENAI_IMAGE_TEXT_INPUT_RATE_MICRODOLLARS_PER_MILLION: z.coerce.number().int().positive(),
  OPENAI_IMAGE_INPUT_RATE_MICRODOLLARS_PER_MILLION: z.coerce.number().int().positive(),
  OPENAI_IMAGE_OUTPUT_RATE_MICRODOLLARS_PER_MILLION: z.coerce.number().int().positive(),
  OPENAI_REQUEST_TIMEOUT_MS: z.coerce.number().int().min(1_000).default(180_000),
  REMOTE_IMAGE_GLOBAL_CONCURRENCY: z.coerce.number().int().positive().default(2),
  REMOTE_IMAGE_ACCOUNT_CONCURRENCY: z.coerce.number().int().positive().default(1),
  REMOTE_IMAGE_LEASE_SECONDS: z.coerce.number().int().positive().default(600),
  REMOTE_IMAGE_POLL_INTERVAL_MS: z.coerce.number().int().min(250).default(1_000),
});

export type WorkerConfig = z.infer<typeof workerConfigSchema>;

export function readWorkerConfig(
  environment: NodeJS.ProcessEnv = process.env,
): WorkerConfig {
  return workerConfigSchema.parse(environment);
}
