import { z } from 'zod';

export const apiConfigSchema = z.object({
  API_HOST: z.string().min(1).default('0.0.0.0'),
  API_PORT: z.coerce.number().int().min(1).max(65535).default(4143),
  DATABASE_URL: z.url(),
  S3_ENDPOINT: z.url(),
  S3_REGION: z.string().min(1),
  S3_BUCKET: z.string().min(3),
  S3_ACCESS_KEY_ID: z.string().min(1),
  S3_SECRET_ACCESS_KEY: z.string().min(1),
  SESSION_SECRET: z.string().min(32),
});

export type ApiConfig = z.infer<typeof apiConfigSchema>;

export function readApiConfig(environment: NodeJS.ProcessEnv = process.env): ApiConfig {
  return apiConfigSchema.parse(environment);
}
