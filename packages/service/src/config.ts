import { z } from 'zod';

export const databaseConfigSchema = z.object({
  DATABASE_URL: z.url(),
});

export const objectStorageConfigSchema = z.object({
  S3_ENDPOINT: z.url(),
  S3_REGION: z.string().min(1),
  S3_BUCKET: z.string().min(3),
  S3_ACCESS_KEY_ID: z.string().min(1),
  S3_SECRET_ACCESS_KEY: z.string().min(1),
  S3_FORCE_PATH_STYLE: z.stringbool().default(true),
});

export type DatabaseConfig = z.infer<typeof databaseConfigSchema>;
export type ObjectStorageConfig = z.infer<typeof objectStorageConfigSchema>;

export function readDatabaseConfig(environment: NodeJS.ProcessEnv = process.env): DatabaseConfig {
  return databaseConfigSchema.parse(environment);
}

export function readObjectStorageConfig(
  environment: NodeJS.ProcessEnv = process.env,
): ObjectStorageConfig {
  return objectStorageConfigSchema.parse(environment);
}
