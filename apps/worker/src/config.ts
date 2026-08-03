import { z } from 'zod';

export const workerConfigSchema = z.object({
  DATABASE_URL: z.url(),
  S3_ENDPOINT: z.url(),
  S3_REGION: z.string().min(1),
  S3_BUCKET: z.string().min(3),
  S3_ACCESS_KEY_ID: z.string().min(1),
  S3_SECRET_ACCESS_KEY: z.string().min(1),
  OPENAI_API_KEY: z.string().min(1),
  REMOTE_IMAGE_GLOBAL_CONCURRENCY: z.coerce.number().int().positive().default(2),
  REMOTE_IMAGE_ACCOUNT_CONCURRENCY: z.coerce.number().int().positive().default(1),
});

export type WorkerConfig = z.infer<typeof workerConfigSchema>;

export function readWorkerConfig(
  environment: NodeJS.ProcessEnv = process.env,
): WorkerConfig {
  return workerConfigSchema.parse(environment);
}
