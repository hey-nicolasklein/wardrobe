import { serve } from '@hono/node-server';
import {
  checkDependencies,
  createDatabase,
  createPrivateObjectStorage,
  ensurePrivateBucket,
  migrateDatabase,
} from '@form/service';

import { createApp } from './app.js';
import { readApiConfig } from './config.js';

const config = readApiConfig();
const database = createDatabase(config);
const storage = createPrivateObjectStorage(config);

await migrateDatabase(database);
await ensurePrivateBucket(storage);

const app = createApp(() => checkDependencies(database, storage));
const server = serve({
  fetch: app.fetch,
  hostname: config.API_HOST,
  port: config.API_PORT,
});

console.log(`FORM API listening on http://${config.API_HOST}:${config.API_PORT}`);

let stopping = false;
async function stop(): Promise<void> {
  if (stopping) return;
  stopping = true;
  server.close();
  storage.client.destroy();
  await database.end();
}

process.once('SIGINT', () => void stop());
process.once('SIGTERM', () => void stop());
