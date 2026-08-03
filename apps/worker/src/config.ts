import { z } from 'zod';
import { serviceConfigSchema } from '@form/service';

export const workerConfigSchema = serviceConfigSchema.extend({
  WORKER_ID: z.string().min(1).default('form-worker'),
  REMOTE_IMAGE_GLOBAL_CONCURRENCY: z.coerce.number().int().positive().default(2),
  REMOTE_IMAGE_ACCOUNT_CONCURRENCY: z.coerce.number().int().positive().default(1),
});

export type WorkerConfig = z.infer<typeof workerConfigSchema>;

export function readWorkerConfig(
  environment: NodeJS.ProcessEnv = process.env,
): WorkerConfig {
  return workerConfigSchema.parse(environment);
}
