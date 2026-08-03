import { z } from 'zod';
import { serviceConfigSchema } from '@form/service';

export const apiConfigSchema = serviceConfigSchema.extend({
  API_HOST: z.string().min(1).default('0.0.0.0'),
  API_PORT: z.coerce.number().int().min(1).max(65535).default(4143),
  SESSION_SECRET: z.string().min(32),
});

export type ApiConfig = z.infer<typeof apiConfigSchema>;

export function readApiConfig(environment: NodeJS.ProcessEnv = process.env): ApiConfig {
  return apiConfigSchema.parse(environment);
}
