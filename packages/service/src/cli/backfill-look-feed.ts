import {
  backfillLookFeedAssets,
  createDatabase,
  createPrivateObjectStorage,
  readDatabaseConfig,
  readObjectStorageConfig,
} from '../index.js';

// Creates the WebP feed copy for looks finished before feed assets existed.
// Only reads originals and adds new assets, so it is safe to re-run.
const database = createDatabase(readDatabaseConfig());
const storage = createPrivateObjectStorage(readObjectStorageConfig());
try {
  const { created, failed } = await backfillLookFeedAssets(database, storage);
  console.log(`Created ${created} feed images, ${failed} failed.`);
  if (failed) process.exitCode = 1;
} finally {
  await database.end();
}
