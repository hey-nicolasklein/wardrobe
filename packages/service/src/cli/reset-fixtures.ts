import {
  createDatabase,
  loadLocalEnvironment,
  PrivateAssetStore,
  readServiceConfig,
  resetFixtures,
  runMigrations,
} from '../index.js';

loadLocalEnvironment();
const config = readServiceConfig();
const database = createDatabase(config.DATABASE_URL);
const assets = new PrivateAssetStore(database, config);

try {
  await runMigrations(database);
  await assets.ensurePrivateBucket();
  await resetFixtures(database, assets);
  console.log('Deterministic fixture accounts reset.');
} finally {
  await database.end();
}
