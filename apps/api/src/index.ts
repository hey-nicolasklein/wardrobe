import { serve } from '@hono/node-server';
import {
  createDatabase,
  loadLocalEnvironment,
  PrivateAssetStore,
  runMigrations,
} from '@form/service';

import { createApp } from './app.js';
import { readApiConfig } from './config.js';

loadLocalEnvironment();
const config = readApiConfig();
const database = createDatabase(config.DATABASE_URL);
const assets = new PrivateAssetStore(database, config);

await runMigrations(database);
await assets.ensurePrivateBucket();
const app = createApp({ database, assets, bucket: config.S3_BUCKET });

const server = serve({
  fetch: app.fetch,
  hostname: config.API_HOST,
  port: config.API_PORT,
});

console.log(`FORM API workspace listening on http://${config.API_HOST}:${config.API_PORT}`);

async function shutdown(): Promise<void> {
  server.close();
  await database.end();
}

process.once('SIGINT', () => void shutdown());
process.once('SIGTERM', () => void shutdown());
