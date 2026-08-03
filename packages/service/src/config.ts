import { z } from 'zod';

export const serviceConfigSchema = z.object({
  DATABASE_URL: z.url(),
  S3_ENDPOINT: z.url(),
  S3_REGION: z.string().min(1),
  S3_BUCKET: z.string().min(3),
  S3_ACCESS_KEY_ID: z.string().min(1),
  S3_SECRET_ACCESS_KEY: z.string().min(1),
});

export type ServiceConfig = z.infer<typeof serviceConfigSchema>;

export function loadLocalEnvironment(path = '.env.local'): void {
  try {
    process.loadEnvFile(path);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
  }
}

export function readServiceConfig(
  environment: NodeJS.ProcessEnv = process.env,
): ServiceConfig {
  return serviceConfigSchema.parse(environment);
}
