import {
  createDatabase,
  createPrivateObjectStorage,
  ensurePrivateBucket,
  migrateDatabase,
  readDatabaseConfig,
  readObjectStorageConfig,
} from '../index.js';
import { resetFixtures } from '../fixtures.js';

if (process.env.FIXTURE_RESET_ALLOWED !== 'true') {
  throw new Error('Refusing to reset fixtures unless FIXTURE_RESET_ALLOWED=true.');
}

const localHostnames = new Set(['localhost', '127.0.0.1', '::1', 'postgres', 'object-storage']);
const databaseUrl = new URL(process.env.DATABASE_URL ?? '');
const storageUrl = new URL(process.env.S3_ENDPOINT ?? '');
if (!localHostnames.has(databaseUrl.hostname) || !localHostnames.has(storageUrl.hostname)) {
  throw new Error('Fixture reset is restricted to local database and object-storage hosts.');
}

const database = createDatabase(readDatabaseConfig());
const storage = createPrivateObjectStorage(readObjectStorageConfig());
try {
  await migrateDatabase(database);
  await ensurePrivateBucket(storage);
  await resetFixtures(database, storage);
  console.log('Reset deterministic fixtures for owner@example.test and empty@example.test.');
} finally {
  storage.client.destroy();
  await database.end();
}
