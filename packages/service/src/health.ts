import { HeadBucketCommand, type S3Client } from '@aws-sdk/client-s3';

import type { Database } from './database.js';

export interface DependencyHealth {
  status: 'ready' | 'not-ready';
  database: 'up' | 'down';
  objectStorage: 'up' | 'down';
}

export async function checkDependencies(
  database: Database,
  storage: S3Client,
  bucket: string,
): Promise<DependencyHealth> {
  const [databaseResult, storageResult] = await Promise.allSettled([
    database.query('SELECT 1'),
    storage.send(new HeadBucketCommand({ Bucket: bucket })),
  ]);
  const databaseState = databaseResult.status === 'fulfilled' ? 'up' : 'down';
  const storageState = storageResult.status === 'fulfilled' ? 'up' : 'down';
  return {
    status:
      databaseState === 'up' && storageState === 'up' ? 'ready' : 'not-ready',
    database: databaseState,
    objectStorage: storageState,
  };
}
