import {
  createDatabase,
  loadLocalEnvironment,
  PrivateAssetStore,
  readServiceConfig,
  runMigrations,
} from '../index.js';

loadLocalEnvironment();
const config = readServiceConfig();
const database = createDatabase(config.DATABASE_URL);

try {
  await runMigrations(database);
  await new PrivateAssetStore(database, config).ensurePrivateBucket();
  console.log('Database migrations applied and private media bucket is ready.');
} finally {
  await database.end();
}
