import type { Database } from './database.js';
import { checkDatabase } from './database.js';
import type { PrivateObjectStorage } from './storage.js';
import { checkObjectStorage } from './storage.js';

export type DependencyHealth = {
  status: 'ready' | 'not-ready';
  database: 'up' | 'down';
  objectStorage: 'up' | 'down';
};

export async function checkDependencies(
  database: Database,
  storage: PrivateObjectStorage,
): Promise<DependencyHealth> {
  const [databaseResult, storageResult] = await Promise.allSettled([
    checkDatabase(database),
    checkObjectStorage(storage),
  ]);
  const health: DependencyHealth = {
    status: databaseResult.status === 'fulfilled' && storageResult.status === 'fulfilled'
      ? 'ready'
      : 'not-ready',
    database: databaseResult.status === 'fulfilled' ? 'up' : 'down',
    objectStorage: storageResult.status === 'fulfilled' ? 'up' : 'down',
  };
  return health;
}
