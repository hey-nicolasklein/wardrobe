import { databaseConfigSchema, objectStorageConfigSchema } from '@form/service';
import { z } from 'zod';

export const apiConfigSchema = z.object({
  ...databaseConfigSchema.shape,
  ...objectStorageConfigSchema.shape,
  API_HOST: z.string().min(1).default('0.0.0.0'),
  API_PORT: z.coerce.number().int().min(1).max(65535).default(4143),
  SESSION_SECRET: z.string().min(32),
  SESSION_LIFETIME_SECONDS: z.coerce.number().int().min(300).default(2_592_000),
  SESSION_COOKIE_SECURE: z.stringbool().default(true),
  OPENAI_DETECTION_MODEL: z.string().min(1).default('gpt-5.4-mini'),
  WEB_ORIGIN: z.url().optional(),
});

export type ApiConfig = z.infer<typeof apiConfigSchema>;

export function readApiConfig(environment: NodeJS.ProcessEnv = process.env): ApiConfig {
  return apiConfigSchema.parse(environment);
}
